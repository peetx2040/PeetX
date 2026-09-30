// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Imports.sol";
import "./PositionManager.sol";
import "./UniswapUtil.sol";
import "./PeetXInvestEngine.sol";

contract PeetXInvest is UniswapUtil, PeetXInvestEngine {
    using SafeERC20 for IERC20;

    address private _owner;
    uint256 private _status;

    uint256 private constant MIN_AMOUNT = 1 * 10**18;

    event PoolEvent(uint256 indexed id, string itemType, address indexed user, uint256 amount, bool success);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier nonReentrant() {
        require(_status != 2, "ReentrancyGuard: reentrant call");
        _status = 2;
        _;
        _status = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Unauthorized");
        _;
    }

    constructor() {
        _owner = address(0);
        _status = 1;
        emit OwnershipTransferred(address(0), address(0));
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function USDT() external view returns (address) {
        return USDT_ADDRESS;
    }

    function NonfungiblePositionManager() external view returns (address) {
        return VAULT_NFT_CONTRACT;
    }

    function Chainlink() external view returns (bool) {
        uint256 limitInv = nextInvestmentId;
        uint256 checkLimit = limitInv > investmentCursor + 50 ? investmentCursor + 50 : limitInv;
        
        for (uint256 i = investmentCursor; i < checkLimit; i++) {
            Investment memory inv = investments[i];
            if (!inv.processed && !inv.earlyWithdrawn) {
                if (block.timestamp >= inv.startTime + inv.duration) {
                    return true;
                }
            }
        }
        return false;
    }

    function View_plans(address user, uint256 invCursor, uint256 invLimit) external view returns (
        UserGenData memory userData,
        Investment[] memory activeInvestments
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
            _withdrawFromNFT(inv.investor, refundable);
        }

        emit PoolEvent(invId, "EARLY_WITHDRAWAL", msg.sender, refundable, true);
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

    function pool() external nonReentrant {
        uint256 processedCount = 0;
        uint256 maxBatch = 20;

        uint256 limitInv = nextInvestmentId;
        uint256 i = investmentCursor;
        while (i < limitInv && processedCount < maxBatch) {
            Investment storage inv = investments[i];
            
            if (inv.processed || inv.earlyWithdrawn) {
                i++;
                continue;
            }

            if (block.timestamp >= inv.startTime + inv.duration) {
                inv.processed = true;
                uint256 totalReturn = inv.amount + ((inv.amount * inv.profitPercent) / 100);
                
                _withdrawFromNFT(inv.investor, totalReturn);

                emit PoolEvent(i, "INVESTMENT_MATURED", inv.investor, totalReturn, true);
                processedCount++;
            }
            i++;
        }
        investmentCursor = i;

        if (investmentCursor >= limitInv) {
            investmentCursor = 0;
        }
    }
}
