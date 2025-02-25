uint256 bettingReceipt;
uint256 fiveBallAmount;
uint256 singleBallAmount;
uint256 ticketMutiplier;

ticketAmount = multiBetFactor[fiveBallAmount-5] * singleBallAmount * ticketMutiplier;

uint256[8]  multiBetFactor = [1,6,21,56,126,252,462,792]; // index - 5


uint256[8]  multiWin3plus1 = [1,3,6,10,15,21,28,36]; // lv5 prize

uint256[8][3]  multiWin4plus1 = [
    [1,2,3,4,5,6,7,8],   // lv3 "4+1" multiWin4plus1[fiveBallAmount-5][0]
    [1,4,12,24,40,60,84,112], // lv4 "3+1" multiWin4plus1[fiveBallAmount-5][1]
    [1,2,3,4,5,6,7,8] // lv5 "4" multiWin4plus1[fiveBallAmount-5][2 * (singleBallAmount -1)
];

// lv1 5+1 amount =   1 无论5球池选多少
// lv2 5  amount =   singleBallAmount -1   无论5球池选多少
uint256[8][3]  multiWin5plus1 = [   // win 4+1 lv3 prize
    [1,5,10,15,20,25,30,35], // lv3 "4+1" multiWin5plus1[fiveBallAmount-5][0]
    [1,6,10,30,60,100,150,210], //lv4 "3+1" multiWin5plus1[fiveBallAmount-5][1]
    [1,5,10,15,20,25,30,35] // lv5 "4" multiWin5plus1[fiveBallAmount-5][2] * (singleBallAmount -1)
];

uint256[8]  multiWin3plus1 = [1,3,6,10,15,21,28,36]; // lv5 prize


/// 彩票收据 2slot
    struct Receipt {
        /// slot 1
        address player;
        uint16 round; /// 65535 / 365 = 179 years
        uint16 fiveBall;
        uint16 oneBall;
        uint32 multiplier; /// 
        /// slot 2
        uint32 lv1; 
        uint32 lv2; 
        uint32 lv3;
        uint32 lv4;
        uint32 lv5; // 上限4亿足够了
        uint8 claimStatus; // 0 = not claimed, 1 = claimed,
        uint8 redeemaStatus;// 0 = not redeemed, 1 = low prize redeemed, 2 = high prize redeemed, 3 = full prize redeemed
    }  

    // 单轮总金额，清算后删除
    struct PrizePool {
        uint128 highPrize; // 56% (0.625 lv1 + 0.375 lv2)
        uint128 lowPrize; // 44% ( lowPrize / 3 => reserves)
    }

    // 计算用，且不删除
    struct LotteryResult {
        uint32 lv1Tickets; // 总注数 最高uint32 4亿
        uint32 lv2Tickets; //  总注数
        uint80 lv1Prize; // 单价  // 最高79亿GLMR
        uint80 lv2Prize; //  单价
        uint16 fiveBall; // 56% (0.625 lv1 + 0.375 lv2)
        uint16 oneBall; // 44% ( lowPrize / 3 => reserves)
    }


    BitMaps.BitMap private betIDClosed;
    BitMaps.BitMap private PrizeClaimOpen;
    BitMaps.BitMap private PrizeRedeemOpen;

    uint128 public betID;
    uint128 public highPrizeReserves;
    uint128 public lowPrizeReserves;
    uint128 private donations;
    uint128 private feeBalance;
    uint16 public round;
    uint8 private randomProvider; // 0: embed 1:proxy(upgradeable)

    mapping(uint256 => Receipt) public ReceiptInfo; /// betID => Receipt

    mapping(address => mapping(uint256 => uint128[])) public playerRecord; // player => round => betIDs

    mapping(uint256 => uint256) public roundStartTime; /// round => timestamp
    mapping(uint256 => PrizePool) public prizePool; /// round => prizePool
    mapping(uint256 => LotteryResult) public lotteryResult; /// round => prizePool

    mapping(uint256 => uint256) charterOwnerRewards; // chartId => Rewards

    uint128[2][] public PriceHistory = [[1 ether , 1]]; // [price,startround]
      
    