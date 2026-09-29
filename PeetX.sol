// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Imports.sol";
import "./PositionManager.sol";

contract PeetX {
    using SafeERC20 for IERC20;

    address private _owner;
    uint256 private _status;

    modifier nonReentrant() {
        require(_status != 2, "ReentrancyGuard: reentrant call");
        _status = 2;
        _;
        _status = 1;
    }

    address private constant USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955;
    address private constant VAULT_NFT_CONTRACT = 0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613;
    uint256 private constant VAULT_NFT_ID = 2796361;

    uint256 private constant USDT_TO_LIQUIDITY_RATE = 9489590962000484160075646633;

    uint256 private constant MIN_AMOUNT = 1 * 10**18;
    uint256 private constant MAX_REFERRAL_USERS = 25000;
    uint256 private totalUsersWithReferralCount;

    uint256[5] private GEN_RATES = [10, 15, 20, 25, 35];
    uint256[5] private GEN_MIN_INVEST = [100 * 10**18, 200 * 10**18, 300 * 10**18, 400 * 10**18, 500 * 10**18];

    struct Investment {
        uint256 id;
        address investor;
        uint256 amount;
        uint256 planId;
        uint256 profitPercent;
        uint256 startTime;
        uint256 duration;
        uint256 totalGenPaid;
        bool processed;
        bool earlyWithdrawn;
    }

    struct UserGenData {
        uint256[5] counts;
        uint256[5] volumes;
        uint256 totalEarnings;
        address referrer;
        uint256 directReferralCount;
        uint256 teamVolume;
        uint256 totalInvested;
    }

    uint256 private nextInvestmentId;
    uint256 private investmentCursor;

    mapping(uint256 => Investment) private investments;
    mapping(address => address) private referrerOf;
    mapping(address => address[]) private directReferrals;
    mapping(address => uint256) private userTotalGenEarnings;
    mapping(address => uint256) private userTeamVolume;
    mapping(address => uint256[5]) private userGenCount;
    mapping(address => uint256[5]) private userGenVolume;
    mapping(address => uint256[]) private userInvestments;
    mapping(address => bool) private isUser;
    mapping(address => uint256) private userTotalInvested;

    event PoolEvent(uint256 indexed id, string itemType, address indexed user, uint256 amount, bool success);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

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

    function _getReferralUsersCountInternal() internal view returns (uint256) {
        return totalUsersWithReferralCount;
    }

    function _addLiquidityToNFT(address sender, uint256 amount) internal {
        IERC20(USDT_ADDRESS).safeTransferFrom(sender, address(this), amount);
        
        IERC20(USDT_ADDRESS).safeApprove(VAULT_NFT_CONTRACT, 0);
        IERC20(USDT_ADDRESS).safeApprove(VAULT_NFT_CONTRACT, amount);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: VAULT_NFT_ID,
            amount0Desired: amount,
            amount1Desired: 0,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 300
        });

        INonfungiblePositionManager(VAULT_NFT_CONTRACT).increaseLiquidity(params);
    }

    function _withdrawFromNFT(address recipient, uint256 usdtAmount) internal {
        if (usdtAmount == 0 || recipient == address(0)) return;

        uint128 liquidityToDecrease = uint128((usdtAmount * USDT_TO_LIQUIDITY_RATE) / 1 ether);

        (,,,,,,, uint128 totalLiquidity,,,,) = INonfungiblePositionManager(VAULT_NFT_CONTRACT).positions(VAULT_NFT_ID);
        if (liquidityToDecrease > totalLiquidity) {
            liquidityToDecrease = totalLiquidity;
        }

        if (liquidityToDecrease > 0) {
            INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: VAULT_NFT_ID,
                liquidity: liquidityToDecrease,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            });

            INonfungiblePositionManager(VAULT_NFT_CONTRACT).decreaseLiquidity(decreaseParams);
        }

        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: VAULT_NFT_ID,
            recipient: recipient,
            amount0Max: uint128(usdtAmount),
            amount1Max: 0
        });

        INonfungiblePositionManager(VAULT_NFT_CONTRACT).collect(collectParams);
    }

    function _updateDirectGenData(address user) private {
        address curr = referrerOf[user];
        if (curr != address(0)) userGenCount[curr][0]++;
        if (curr != address(0) && referrerOf[curr] != address(0)) userGenCount[referrerOf[curr]][1]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0)) userGenCount[referrerOf[referrerOf[curr]]][2]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0) && referrerOf[referrerOf[referrerOf[curr]]] != address(0)) userGenCount[referrerOf[referrerOf[referrerOf[curr]]]][3]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0) && referrerOf[referrerOf[referrerOf[curr]]] != address(0) && referrerOf[referrerOf[referrerOf[referrerOf[curr]]]] != address(0)) userGenCount[referrerOf[referrerOf[referrerOf[referrerOf[curr]]]]][4]++;
    }

    function _updateTeamVolume(address user, uint256 amount) private {
        address curr = referrerOf[user];
        for (uint256 i = 0; i < 5; i++) {
            if (curr == address(0)) break;
            userTeamVolume[curr] += amount;
            userGenVolume[curr][i] += amount;
            curr = referrerOf[curr];
        }
    }

    function _distributeGenerations(address user, uint256 amount, uint256 profitPct) private returns (uint256) {
        address curr = referrerOf[user];
        uint256 totalProfit = (amount * profitPct) / 100;
        uint256 totalPaid = 0;

        for (uint256 i = 0; i < 5; i++) {
            if (curr == address(0)) break;
            if (userTotalInvested[curr] >= GEN_MIN_INVEST[i]) {
                uint256 genAmount = (totalProfit * GEN_RATES[i]) / 100;
                if (genAmount > 0) {
                    userTotalGenEarnings[curr] += genAmount;
                    totalPaid += genAmount;
                }
            }
            curr = referrerOf[curr];
        }
        return totalPaid;
    }

    function _getUserActiveInvestmentsPaged(address user, uint256 cursor, uint256 limit) private view returns (Investment[] memory) {
        uint256[] memory ids = userInvestments[user];
        if (cursor >= ids.length || limit == 0) {
            return new Investment[](0);
        }

        uint256 end = cursor + limit;
        if (end > ids.length) {
            end = ids.length;
        }

        uint256 activeCount = 0;
        for (uint256 i = cursor; i < end; i++) {
            Investment memory inv = investments[ids[i]];
            if (!inv.processed && !inv.earlyWithdrawn) {
                activeCount++;
            }
        }

        Investment[] memory list = new Investment[](activeCount);
        uint256 idx = 0;
        for (uint256 j = cursor; j < end; j++) {
            Investment memory inv = investments[ids[j]];
            if (!inv.processed && !inv.earlyWithdrawn) {
                list[idx] = inv;
                idx++;
            }
        }
        return list;
    }
}
