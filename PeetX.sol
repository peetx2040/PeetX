contract PeetX is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address private _owner;
    bool private _isRenounced;

    address private constant USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955;
    address private constant VAULT_NFT_CONTRACT = 0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613;
    uint256 private constant VAULT_NFT_ID = 2536921;

    int24 private constant TICK_LOWER = 200310;
    int24 private constant TICK_UPPER = 230270;

    address private constant CHAINLINK_FEED = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE;

    uint256 private constant MIN_AMOUNT = 1 * 10**18;
    uint256 private constant MIN_TRADE_AMOUNT = 10 * 10**18;
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

    uint256 private nextInvestmentId;
    uint256 private nextTradeId;
    uint256 private investmentCursor;
    uint256 private tradeCursor;

    mapping(uint256 => Investment) private investments;
    mapping(uint256 => Trade) private trades;
    mapping(address => address) private referrerOf;
    mapping(address => address[]) private directReferrals;
    mapping(address => uint256) private userTotalGenEarnings;
    mapping(address => uint256) private userTeamVolume;
    mapping(address => uint256[5]) private userGenCount;
    mapping(address => uint256[5]) private userGenVolume;
    mapping(address => uint256[]) private userInvestments;
    mapping(address => uint256[]) private userTrades;
    mapping(address => bool) private isUser;
    mapping(address => uint256) private userTotalInvested;

    event PoolEvent(uint256 indexed id, string itemType, address indexed user, uint256 amount, bool success);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(!_isRenounced && msg.sender == _owner, "Unauthorized");
        _;
    }

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }
}
