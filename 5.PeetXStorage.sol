// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ReentrancyGuard.sol";

abstract contract PeetXStorage is ReentrancyGuard {
    address internal _owner;
    bool internal _isRenounced;

    address internal constant USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955;
    address internal constant VAULT_NFT_CONTRACT = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    uint256 internal constant VAULT_NFT_ID = 2536921;

    address internal constant CHAINLINK_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;

    uint256 internal constant MIN_AMOUNT = 1 * 10**18;
    uint256 internal constant MIN_TRADE_AMOUNT = 10 * 10**18;
    uint256 internal constant MAX_REFERRAL_USERS = 25000;
    uint256 internal totalUsersWithReferralCount;

    uint256[5] internal GEN_RATES = [10, 15, 20, 25, 35];
    uint256[5] internal GEN_MIN_INVEST = [25 * 10**18, 50 * 10**18, 100 * 10**18, 150 * 10**18, 200 * 10**18];

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

    struct Trade {
        uint256 id;
        address trader;
        uint256 amount;
        uint256 duration;
        uint256 startTime;
        bool isBuy;
        uint256 entryPrice;
        bool processed;
        bool won;
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

    uint256 internal nextInvestmentId;
    uint256 internal nextTradeId;

    mapping(uint256 => Investment) internal investments;
    mapping(uint256 => Trade) internal trades;

    mapping(address => address) internal referrerOf;
    mapping(address => address[]) internal directReferrals;
    mapping(address => uint256) internal userTotalGenEarnings;
    mapping(address => uint256) internal userTeamVolume;
    mapping(address => uint256[5]) internal userGenCount;
    mapping(address => uint256[5]) internal userGenVolume;

    mapping(address => uint256[]) internal userInvestments;
    mapping(address => uint256[]) internal userTrades;

    mapping(address => bool) internal isUser;
    mapping(address => uint256) internal userTotalInvested;

    event PoolEvent(uint256 indexed id, string itemType, address indexed user, uint256 amount, bool success);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
}
