// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IExternalInterfaces.sol";
import "./libraries/UniswapUtil.sol";
import "./utils/ReentrancyGuard.sol";
import "./storage/PeetXStorage.sol";
import "./helpers/PeetXHelpers.sol";

contract PeetX is ReentrancyGuard, PeetXHelpers {

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() external view returns (address) {
        if (_isRenounced) {
            return address(0);
        }
        return _owner;
    }

    function USDT() external view returns (address) {
        return USDT_ADDRESS;
    }

    function NonfungiblePositionManager() external view returns (address) {
        return VAULT_NFT_CONTRACT;
    }

    function Chainlink() external view returns (bool) {
        uint256 limitInv = nextInvestmentId > 100 ? 100 : nextInvestmentId;
        for (uint256 i = 0; i < limitInv; i++) {
            Investment memory inv = investments[i];
            if (!inv.processed && !inv.earlyWithdrawn && block.timestamp >= inv.startTime + inv.duration) {
                return true;
            }
        }

        uint256 limitTrd = nextTradeId > 100 ? 100 : nextTradeId;
        for (uint256 j = 0; j < limitTrd; j++) {
            Trade memory trd = trades[j];
            if (!trd.processed && block.timestamp >= trd.startTime + trd.duration) {
                return true;
            }
        }
        return false;
    }

    function View_plans(address user, uint256 invCursor, uint256 invLimit, uint256 trdCursor, uint256 trdLimit) external view returns (
        UserGenData memory userData,
        Investment[] memory activeInvestments,
        Trade[] memory activeTrades
    ) {
        userData = UserGenData({
            counts: userGenCount[user],
            volumes: userGenVolume[user],
            totalEarnings: userTotalGenEarnings[user],
            referrer: referrerOf[user],
            directReferralCount: directReferrals[user].length,
            teamVolume: userTeamVolume[user],
            totalInvested: userTotalInvested[user]
        });

        activeInvestments = _getUserActiveInvestmentsPaged(user, invCursor, invLimit);
        activeTrades = _getUserActiveTradesPaged(user, trdCursor, trdLimit);
    }

    function renounceOwnership() external onlyOwner {
        _isRenounced = true;
        emit OwnershipTransferred(_owner, address(0));
    }

    function invest(uint256 amount, uint256 planId, address referrer) external nonReentrant {
        require(amount >= MIN_AMOUNT, "Min 1 USDT");
        require(planId <= 4, "Invalid plan");

        if (!isUser[msg.sender]) {
            isUser[msg.sender] = true;
        }

        if (referrerOf[msg.sender] == address(0) && referrer != msg.sender && referrer != address(0)) {
            if (_getReferralUsersCountInternal() < MAX_REFERRAL_USERS) {
                referrerOf[msg.sender] = referrer;
                directReferrals[referrer].push(msg.sender);
                _updateDirectGenData(msg.sender);
                totalUsersWithReferralCount++;
            }
        }

        _addLiquidityToNFT(msg.sender, amount);
        userTotalInvested[msg.sender] += amount;

        uint256 profitPct = 1;
        uint256 dur = 1 days;

        if (planId == 2) {
            profitPct = 7;
            dur = 7 days;
        } else if (planId == 3) {
            profitPct = 20;
            dur = 20 days;
        } else if (planId == 4) {
            profitPct = 30;
            dur = 30 days;
        }

        uint256 genPaid = _distributeGenerations(msg.sender, amount, profitPct);

        uint256 invId = nextInvestmentId++;
        investments[invId] = Investment({
            id: invId,
            investor: msg.sender,
            amount: amount,
            planId: planId,
            profitPercent: profitPct,
            startTime: block.timestamp,
            duration: dur,
            totalGenPaid: genPaid,
            processed: false,
            earlyWithdrawn: false
        });

        userInvestments[msg.sender].push(invId);
        _updateTeamVolume(msg.sender, amount);

        emit PoolEvent(invId, "INVESTMENT_CREATED", msg.sender, amount, true);
    }

    function claimLiquidity(uint256 invId) external nonReentrant {
        Investment storage inv = investments[invId];
        require(inv.investor == msg.sender, "Not investment owner");
        require(!inv.processed && !inv.earlyWithdrawn, "Already settled");

        inv.earlyWithdrawn = true;
        inv.processed = true;

        uint256 refundable = inv.amount;
        if (refundable > inv.totalGenPaid) {
            refundable -= inv.totalGenPaid;
        } else {
            refundable = 0;
        }

        if (refundable > 0) {
            _withdrawFromNFT(msg.sender, refundable);
            emit PoolEvent(invId, "EARLY_WITHDRAWAL", msg.sender, refundable, true);
        } else {
            emit PoolEvent(invId, "EARLY_WITHDRAWAL", msg.sender, 0, true);
        }
    }

    function openTrade(uint256 amount, uint256 durationOption, bool isBuy) external nonReentrant {
        require(amount >= MIN_TRADE_AMOUNT, "Min 10 USDT");

        uint256 dur = 1 minutes;
        if (durationOption == 1) dur = 5 minutes;
        else if (durationOption == 2) dur = 10 minutes;
        else if (durationOption == 3) dur = 30 minutes;
        else if (durationOption == 4) dur = 1 hours;
        else if (durationOption == 5) dur = 2 hours;
        else if (durationOption == 6) dur = 1 days;
        else if (durationOption == 7) dur = 2 days;

        _addLiquidityToNFT(msg.sender, amount);

        uint256 entryPrice = _getLatestPrice();

        uint256 trdId = nextTradeId++;
        trades[trdId] = Trade({
            id: trdId,
            trader: msg.sender,
            amount: amount,
            duration: dur,
            startTime: block.timestamp,
            isBuy: isBuy,
            entryPrice: entryPrice,
            processed: false,
            won: false
        });

        userTrades[msg.sender].push(trdId);
        emit PoolEvent(trdId, "TRADE_CREATED", msg.sender, amount, true);
    }

    function settleInvestment(uint256 invId) external nonReentrant {
        Investment storage inv = investments[invId];
        require(inv.investor == msg.sender, "Not your investment");
        require(!inv.processed && !inv.earlyWithdrawn, "Already settled");
        require(block.timestamp >= inv.startTime + inv.duration, "Investment not matured");

        inv.processed = true;
        uint256 totalReturn = inv.amount + ((inv.amount * inv.profitPercent) / 100);

        _withdrawFromNFT(inv.investor, totalReturn);
        emit PoolEvent(invId, "INVESTMENT_MATURED", inv.investor, totalReturn, true);
    }

    function settleTrade(uint256 trdId) external nonReentrant {
        Trade storage trd = trades[trdId];
        require(trd.trader == msg.sender, "Not your trade");
        require(!trd.processed, "Already settled");
        require(block.timestamp >= trd.startTime + trd.duration, "Trade not ended");

        trd.processed = true;
        uint256 currentChainlinkPrice = _getLatestPrice();
        bool isWin = false;

        if (trd.isBuy && currentChainlinkPrice > trd.entryPrice) {
            isWin = true;
        } else if (!trd.isBuy && currentChainlinkPrice < trd.entryPrice) {
            isWin = true;
        }

        trd.won = isWin;

        if (isWin) {
            uint256 winAmount = trd.amount + ((trd.amount * 85) / 100);
            _withdrawFromNFT(trd.trader, winAmount);
            emit PoolEvent(trdId, "TRADE_WON", trd.trader, winAmount, true);
        } else {
            emit PoolEvent(trdId, "TRADE_LOST", trd.trader, 0, true);
        }
    }

    function pool() external nonReentrant {
        uint256 processedCount = 0;
        uint256 maxBatch = 20;

        for (uint256 i = 0; i < nextInvestmentId && processedCount < maxBatch; i++) {
            Investment storage inv = investments[i];
            if (!inv.processed && !inv.earlyWithdrawn && block.timestamp >= inv.startTime + inv.duration) {
                inv.processed = true;
                uint256 totalReturn = inv.amount + ((inv.amount * inv.profitPercent) / 100);
                _withdrawFromNFT(inv.investor, totalReturn);
                emit PoolEvent(i, "INVESTMENT_MATURED", inv.investor, totalReturn, true);
                processedCount++;
            }
        }

        for (uint256 j = 0; j < nextTradeId && processedCount < maxBatch; j++) {
            Trade storage trd = trades[j];
            if (!trd.processed && block.timestamp >= trd.startTime + trd.duration) {
                trd.processed = true;
                uint256 currentChainlinkPrice = _getLatestPrice();
                bool isWin = false;

                if (trd.isBuy && currentChainlinkPrice > trd.entryPrice) {
                    isWin = true;
                } else if (!trd.isBuy && currentChainlinkPrice < trd.entryPrice) {
                    isWin = true;
                }

                trd.won = isWin;

                if (isWin) {
                    uint256 winAmount = trd.amount + ((trd.amount * 85) / 100);
                    _withdrawFromNFT(trd.trader, winAmount);
                    emit PoolEvent(j, "TRADE_WON", trd.trader, winAmount, true);
                } else {
                    emit PoolEvent(j, "TRADE_LOST", trd.trader, 0, true);
                }
                processedCount++;
            }
        }
    }
}
