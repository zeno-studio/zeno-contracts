//SPDX-License-Identifier: MIT
pragma solidity  0.8.28;

import {Ownable} from "solady-0.0.265/auth/Ownable.sol";
import {ReentrancyGuardTransient} from "solady-0.0.265/utils/ReentrancyGuardTransient.sol";
import {BitMaps} from "@openzeppelin-contracts-5.1.0/utils/structs/BitMaps.sol";
import {IERC721} from "@openzeppelin-contracts-5.1.0/token/ERC721/IERC721.sol";


contract ZenoMiniBall is Ownable, ReentrancyGuardTransient {

    using BitMaps for BitMaps.BitMap;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS  
    //////////////////////////////////////////////////////////////*/

    // Replace with the address of the fee receiver contract
    address immutable _FEE_RECEIVER;
    address immutable _CHARTER_NFT;

    uint256 constant _MAX_uint16 = type(uint16).max;
    uint256 constant _MAX_uint32 = type(uint32).max;

    /// constant for popcount256B
    uint256 private constant m1 = 0x5555555555555555555555555555555555555555555555555555555555555555;
    uint256 private constant m2 = 0x3333333333333333333333333333333333333333333333333333333333333333;
    uint256 private constant m4 = 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f;
    uint256 private constant h01 = 0x0101010101010101010101010101010101010101010101010101010101010101;


    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS 
    //////////////////////////////////////////////////////////////*/

    error CanNotReceivePaymentsWithUnknownCalldata();

    /*//////////////////////////////////////////////////////////////
                                EVENTS 
    //////////////////////////////////////////////////////////////*/

    event DonationReceived(
        address indexed donor, 
        uint256 indexed amount
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE 
    //////////////////////////////////////////////////////////////*/

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
        uint8 lowPrizeRedeemStatus; // 0 = not redeemed
        uint8 highPrizeRedeemaStatus;// 0 = not redeemed,
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

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address ZenoTokenAddress) {
        _FEE_RECEIVER = ZenoTokenAddress;
        _initializeOwner(msg.sender);

    }

    receive () external payable {
        donate();
    }

    fallback() external payable {
        revert CanNotReceivePaymentsWithUnknownCalldata();
    }

    function donate() internal nonReentrant returns (bool) {
        donations += msg.value;
        emit DonationReceived(msg.sender, msg.value);
        return true;
    }


    /*//////////////////////////////////////////////////////////////
                             LOTTERY LOGIC 
    //////////////////////////////////////////////////////////////*/


    function  caculateHighPrizeRemaining(uint256 _round) internal view returns (uint256){
       
        uint256 lv1Remaining ;
        uint256 lv2Remaining ;
        uint256 lv1Tickets = lotteryResult[_round].lv1Tickets;
        uint256 lv2Tickets = lotteryResult[_round].lv2Tickets; 
        uint256 highPrize = prizePool[_round].highPrize;
        uint256 highPrizeRemaining ;
        
        if (lv1Tickets == 0) {
            lv1Remaining = highPrize * 625 / 1000;  
        }else {
            lv1Remaining = 0;
            uint256 lv1Amount = highPrize * 625 / 1000;
            lotteryResult[_round].lv1Prize = uint80(lv1Amount / lv1Tickets); // 计算储存头奖单价
            highPrizeReserves += uint128(lv1Amount); // 支付转移到储备库
        }

        if (lotteryResult[_round].lv2Tickets == 0) {
            lv2Remaining = highPrize * 375 / 1000;
        }else {
            lv2Remaining = 0;
            uint256 lv2Amount = highPrize * 375 / 1000;
            lotteryResult[_round].lv2Prize = uint80(lv2Amount / lv2Tickets);  // 计算储存头奖单价
            highPrizeReserves += uint128(lv2Amount); // 支付转移到储备库
        }

        highPrizeRemaining = lv1Remaining + lv2Remaining; // 计算剩余可转移奖金
        delete prizePool[_round].highPrize;
        PrizeClaimClosed.set(_round); // disable highPrizeClaim
        return highPrizeRemaining;
    }

    function  caculateLowPrizeRemaining(uint256 _round) internal view returns (uint256){
        uint256 toReserves = prizePool[_round].lowPrize / 3;
        uint256 lowPrizeRemaining = prizePool[round].lowPrize - toReserves;
        lowPrizeReserves += uint128(toReserves);
        delete prizePool[_round].lowPrize;
        return lowPrizeRemaining;
    }

    function pickWinNumber(uint256 _round) internal {
        
    }

    function startNewRound() external returns (uint256) {
        uint256 _round = round;
        if (roundStartTime(_round) + 1 days > block.timestamp) {
            revert RoundIsNotOver();
        }
        //清算捐赠
        uint256 donationsForRound = donations / 3;
        donations -= uint128(donationsForRound);

        if (Round > 3) {  // 清算 round-3轮
        prizePool[_round+1].highPrize = uint128(caculateHighPrizeRemaining(_round-3) + donationsForRound * 56 / 100);
        prizePool[_round+1].lowPrize =  uint128(caculateLowPrizeRemaining(_round-3) + donationsForRound * 44 / 100);

        } else {
            prizePool[_round+1].highPrize = donationsForRound * 56 / 100;
            prizePool[_round+1].lowPrize = donationsForRound * 44 / 100;
        }
        // get random number[6]
        pickWinNumber(_round); 
        roundStartTime[_round+1] = block.timestamp;
        ++round;
        uint256 newRound = round;
        emit RoundStarted(newRound);
        return newRound;
    }

    function fufillWinNumber(uint256[6] _random) external nonReentrant {

        openPrizeClaim.set(round - 1);
    }

    /// 重载函数
    function bet(uint256 _fiveBall, uint256 _oneBall,uint256 _multiplier) external nonReentrant {
        bet (_fiveBall, _oneBall,_multiplier, 0);
    }

    function bet(uint256 _fiveBall, uint256 _oneBall,uint256 _multiplier, uint256 _couponCode) external nonReentrant {
        if (_fiveBall == 0 || _oneBall == 0 && _multiplier == 0) {
            revert InvalidBetTicket();
        }
        /// 不能前12个数重复1
        if (_fiveBall > 65520 || _oneBall > 65520 ) {
            revert InvalidBetTicket();
        }
        if (_multiplier > _MAX_uint32) {
            revert multiplierMustBeLessThanMaxUint32();
        }
        uint256 countA = popcount256B(_fiveBall);
        uint256 countB = popcount256B(_oneBall);
        if (countA > 12 || countB > 12 ) {
            revert multiBetNumberMustBeLessThan12();
        }
        uint256[8] memory multiBetFactor = [1,6,21,56,126,252,462,792]; // index - 5
        uint256 ticketAmount = multiBetFactor[countA-5] * countB * _multiplier;
        uint256 payment = ticketAmount * getTicketPrice(round);
       
        uint256 fee;
        uint256 income;
        uint256 _round = round;
        if (_couponCode == 0 || _couponCode > 9999) {
            if (payment > msg.value) {
            revert NotEnoughFund();
            }
            fee = payment * 2 / 100;
            feeBalance += uint128(fee); // add fee;
            income = payment - fee;
            prizePool[_round].highPrize += uint128(income * 56 / 100);
            prizePool[_round].lowPrize += uint128(income * 44 / 100);
        } else {
            if (payment * 97 / 100 > msg.value) {
            revert NotEnoughFund();
            }
            charterOwnerRewards[_couponCode] += payment * 5 / 100;
            fee = payment * 2 / 100;
            feeBalance += uint128(fee); // add fee;
            income = payment * 90 / 100 ;
            prizePool[_round].highPrize += uint128(income * 56 / 100);
            prizePool[_round].lowPrize += uint128(income * 44 / 100);
        }
        ++betID;
        uint256 _betID = betID;
        ReceiptInfo[_betID] = Receipt({
            player: msg.sender,
            round: uint16(_round),
            fiveBall: uint16(_fiveBall),
            oneBall: uint16(_oneBall),
            multiplier: uint32(_multiplier)
        });
        playerRecord[msg.sender][_round].push(_betID);
    }

    function claimCharterRewards(uint256 _tokenId) external payable nonReentrant {
        IERC721 nftContract = IERC721(_CHARTER_NFT);
        if (nftContract.ownerOf(_tokenId) != msg.sender) {
            revert NFTNotOwnedByMsgSender();
        }
        if (charterOwnerRewards[_tokenId] == 0) {
            revert NoCharterRewards();
        }
        uint256 rewards = charterOwnerRewards[_tokenId];
        charterOwnerRewards[_tokenId] = 0;
        payable(msg.sender).transfer(rewards);
    }

    function claimPrizeByRound(uint256 _round) external nonReentrant {
        if (_round > round) {
            revert RoundNotActive();
        }
        if (!PrizeClaimOpen.get(_round)) {
            revert RoundIsNotOpenToClaim();
        }
        uint256 length = playerRecord[msg.sender][_round].length;
        if (length == 0) {
            revert NoBettingRecord();
        }
        uint256 lowPrizePayment_;
        uint256[] claimedBetID_;
        for (uint256 i = 0; i < length; ++i) {
            uint256 _betID = playerRecord[msg.sender][_round][i];

            if (ReceiptInfo[betId].prizeClaimStatus = 1) {
                revert AlreadyClaimed();
            }
            uint256 fiveBall = ReceiptInfo[betId].fiveBall;
            uint256 oneBall = ReceiptInfo[betId].oneBall;
            uint256 multiplier = ReceiptInfo[betId].multiplier;
            uint256 price = getTicketPrice(_round);
            uint256[4] result = NumberCount(fiveBall, oneBall);

            if (result[2] == 5 && result[3] == 1){
               lowPrizePayment_ += Win5plus1(_betID, multiplier, price, result);
            }
            if (result[2] == 5 && result[3] == 0){
               lowPrizePayment_ += Win5(_betID, multiplier, price, result);
            }
            if (result[2] == 4 && result[3] == 1){
               lowPrizePayment_ += Win4plus1(_betID, multiplier, price, result);
            }
            if (result[2] == 4 && result[3] == 0){
               lowPrizePayment_ += Win4(_betID, multiplier, price, result);
            }
            if (result[2] == 3 && result[3] == 1){
               lowPrizePayment_ += Win3plus1(_betID, multiplier, price, result);
            }
            claimedBetID_.push(_betID);
        }

        if (lowPrizePayment_ < prizePool[_round].lowPrize) {
            prizePool[_round].lowPrize -= lowPrizePayment_;
            for (uint256 i = 0; i < length; ++i) {
            uint256 _betID = playerRecord[msg.sender][_round][i];
            ReceiptInfo[_betID].lowPrizeRedeemStatus = uint8(1);
            }        
            payable(msg.sender).transfer(lowPrizePayment_ );
            emit lowPrizeRedeemedByRound(msg.sender,lowPrizePayment_,_round,claimedBetID_);
        } 

        emit prizesClaimedByRound(msg.sender,_round,claimedBetID_);
    }

    function claimPrizeByID(uint256 _betID) external nonReentrant {
        if (_betID == 0 || _betID > betID) {
            revert InvalidBetID();
        }
        uint256 _round = ReceiptInfo[_betID].round;
        if (_round > round) {
            revert RoundNotActive();
        }
        if (!PrizeClaimOpen.get(_round)) {
            revert RoundIsNotOpenToClaim();
        }
        if (ReceiptInfo[betId].prizeClaimStatus = 1 ) {
                revert AlreadyClaimed();
            }
            uint256 fiveBall = ReceiptInfo[betId].fiveBall;
            uint256 oneBall = ReceiptInfo[betId].oneBall;
            uint256 multiplier = ReceiptInfo[betId].multiplier;
            uint256 price = getTicketPrice(_round);
            uint256[4] result = NumberCount(fiveBall, oneBall);
            uint256 lowPrizePayment_;
            
        if (result[2] == 5 && result[3] == 1){
            lowPrizePayment_ += Win5plus1(_betID, multiplier, price, result);
        }
        if (result[2] == 5 && result[3] == 0){
            lowPrizePayment_ += Win5(_betID, multiplier, price, result);
        }
        if (result[2] == 4 && result[3] == 1){
            lowPrizePayment_ += Win4plus1(_betID, multiplier, price, result);
        }
        if (result[2] == 4 && result[3] == 0){
            lowPrizePayment_ += Win4(_betID, multiplier, price, result);
        }
        if (result[2] == 3 && result[3] == 1){
            lowPrizePayment_ += Win3plus1(_betID, multiplier, price, result);
        }
        
        if (lowPrizePayment_ < prizePool[_round].lowPrize) {
            prizePool[_round].lowPrize -= lowPrizePayment_;
            ReceiptInfo[_betID].lowPrizeRedeemStatus = uint8(1);
            payable(msg.sender).transfer(lowPrizePayment_ );
            emit lowPrizeRedeemedByID(msg.sender,lowPrizePayment_,_round,_betID);
        } 

        emit prizesClaimedByRound(msg.sender,_round,claimedBetID_);

    }


    function Win5plus1(
        uint256 _betID,
        uint256 _multiplier, 
        uint256 _price , 
        uint256[4] memory _result
        ) internal returns (uint256 ) {      
        uint256[8][3]  multiWin5plus1 = [   // win 4+1 lv3 prize
        [1,5,10,15,20,25,30,35], // lv3 "4+1" multiWin5plus1[fiveBallAmount-5][0]
        [1,6,10,30,60,100,150,210], //lv4 "3+1" multiWin5plus1[fiveBallAmount-5][1]
        [1,5,10,15,20,25,30,35] // lv5 "4" multiWin5plus1[fiveBallAmount-5][2] * (oneBallAmount -1)
        ];
        /// 记录高等级
        ReceiptInfo[_betID].claimStatus = uint8(1);
        uint256 lv1 = multiplier;
        uint256 lv2  = (result[1]-1) * multiplier;
        ReceiptInfo[_betID].lv1Prize = uint32(lv1 ) ;
        ReceiptInfo[_betID].lv2Prize = uint32(lv2);
        lotteryResult[round].lv1Tickets += lv1;
        lotteryResult[round].lv2Tickets += lv2;

        // 计算低等级
        uint256 lv3 = multiWin5plus1[result[0]-5][0] * multiplier ;
        uint256 lv4  = multiWin5plus1[result[0]-5][1] * multiplier ;
        uint256 lv5  = multiWin5plus1[result[0]-5][2] * (result[1]-1) * multiplier;
        ReceiptInfo[_betID].lv3Prize = uint32(lv3 );
        ReceiptInfo[_betID].lv4Prize = uint32(lv4 );
        ReceiptInfo[_betID].lv5Prize = uint32(lv5 );
        uint256 Payment = ((lv3 * 200 + lv4 * 20 + lv5 * 10) * price);
        return Payment;   
    }

    function Win5(
        uint256 _betID,
        uint256 _multiplier, 
        uint256 _price , 
        uint256[4] memory _result
        ) internal returns (uint256 ) {      
        uint256[8] multiWin5 =[1,5,10,15,20,25,30,35]; // lv5 "4" multiWin5plus1[fiveBallAmount-5][0]
        /// 记录高等级
        ReceiptInfo[_betID].claimStatus = uint8(1);
        uint256 lv2  = (result[1]) * multiplier;
        ReceiptInfo[_betID].lv2Prize = uint32(lv2 );
        lotteryResult[round].lv2Tickets += lv2;


        // 计算低等级
        uint256 lv5  = multiWin5[result[0]-5] * result[1] * multiplier  ;
        ReceiptInfo[_betID].lv5Prize = uint32(lv5 );
        uint256 Payment_ = lv5 * 10 * price;
        return Payment;   
    }

    function Win4plus1(
        uint256 _betID,
        uint256 _multiplier, 
        uint256 _price , 
        uint256[4] memory _result) internal  {      

        uint256[8][3]  multiWin4plus1 = [
        [1,2,3,4,5,6,7,8],   // lv3 "4+1" multiWin4plus1[fiveBallAmount-5][0]
        [1,4,12,24,40,60,84,112], // lv4 "3+1" multiWin4plus1[fiveBallAmount-5][1]
        [1,2,3,4,5,6,7,8] // lv5 "4" multiWin4plus1[fiveBallAmount-5][2 * (singleBallAmount -1)
        ];
        /// 记录高等级
        ReceiptInfo[_betID].claimStatus = uint8(1);

        // 计算低等级
        uint256 lv3 = multiWin4plus1[result[0]-5][0] * multiplier ;
        uint256 lv4  = multiWin4plus1[result[0]-5][1] * multiplier ;
        uint256 lv5  = multiWin4plus1[result[0]-5][2] * (result[1]-1) * multiplier;
        ReceiptInfo[_betID].lv3Prize = uint32(lv3);
        ReceiptInfo[_betID].lv4Prize = uint32(lv4);
        ReceiptInfo[_betID].lv5Prize = uint32(lv5);
        uint256 Payment = ((lv3 * 200 + lv4 * 20 + lv5 * 10) * price);
        return Payment;   
    }

    function Win3plus1(
        uint256 _betID,
        uint256 _multiplier, 
        uint256 _price , 
        uint256[4] memory _result) internal  {      

        uint256[8]  multiWin3plus1 = [1,3,6,10,15,21,28,36]; // lv4 prize
        /// 记录高等级
        ReceiptInfo[_betID].claimStatus = uint8(1);

        // 计算低等级
        uint256 lv4  = multiWin3plus1[result[0]-5] * multiplier;
        ReceiptInfo[_betID].lv4Prize = uint32(lv4);

        uint256 Payment = lv4 * 20 * pric;
        return Payment;   
    }

    function Win4(
        uint256 _betID,
        uint256 _multiplier, 
        uint256 _price , 
        uint256[4] memory _result
        ) internal returns (uint256 ) {      
        uint256[8] multiWin4 =[1,2,3,4,5,6,7,8]; // lv5 "4" multiWin5plus1[fiveBallAmount-5][0]
        /// 记录高等级
        ReceiptInfo[_betID].claimStatus = uint8(1);
        // 计算低等级
        uint256 lv5  = multiWin5[result[0]-5]  * multiplier  ;
        ReceiptInfo[_betID].lv5Prize = uint32(lv5 );
        uint256 Payment_ = lv5 * 10 * price;
        return Payment;   
    }


    function redeemByRound(uint256 _round) external nonReentrant returns (bool) {
        if (!PrizeRedeemOpen.get(_round)) {
            revert RoundIsNotOpenToRedeem();
        }

        uint256 length = playerRecord[msg.sender][_round].length;
        uint256 price = getTicketPrice(_round);
        uint256 lv1;
        uint256 lv2;
        uint256 lv3;
        uint256 lv4;
        uint256 lv5;
        for (uint256 i = 0 ; i < length; ++i) {
            uint256 _betID = playerRecord[msg.sender][_round][i];
            if (ReceiptInfo[_betID].lowPrizeRedeemStatus = 0 && _betID != 0) {
                lv3 += ReceiptInfo[_betID].lv3Prize;
                lv4 += ReceiptInfo[_betID].lv4Prize;
                lv5 += ReceiptInfo[_betID].lv5Prize;
            }
            if (ReceiptInfo[_betID].highPrizeRedeemStatus = 0 && _betID != 0) {
                lv1 += ReceiptInfo[_betID].lv1Prize;
                lv2 += ReceiptInfo[_betID].lv2Prize;
            }

        }
        uint256 lowPrizePayment = (lv3 * 200 + lv4 * 20 + lv5 * 10) * price;

        if (lowPrizePayment > 0 && lowPrizePayment < lowPrizeReserves) {
            lowPrizeReserves -= lowPrizePayment_;
            for (uint256 i = 0; i < length; ++i) {
                uint256 _betID = playerRecord[msg.sender][_round][i];
                if (_betID != 0) {
                    ReceiptInfo[_betID].lowPrizeRedeemStatus = uint8(1);
                }
            }
            payable(msg.sender).transfer(lowPrizePayment);
            emit lowPrizeRedeemedByRound(msg.sender,lowPrizePayment,_round);
        } 
        
        if (lv1 > 0) {
            lv1Payment = lv1 * LotteryResult[_round].lv1Prize;
        }
        if (lv2 > 0) {
            lv2Payment = lv2 * LotteryResult[_round].lv2Prize;
        }
         uint256 highPrizePayment = lv1Payment + lv2Payment;

        if (highPrizePayment > 0 && highPrizePayment < highPrizeReserves) {
            highPrizeReserves -= highPrizePayment;
            for (uint256 i = 0; i < length; ++i) {
                uint256 _betID = playerRecord[msg.sender][_round][i];
                if (_betID != 0) {
                    ReceiptInfo[_betID].highPrizeRedeemStatus = uint8(1);
                }
            }
            payable(msg.sender).transfer(highPrizePayment);
            emit highPrizeRedeemedByRound(msg.sender,highPrizePayment,_round);
        }
        return true;
    }

    function redeemByID(uint256 _betID) external nonReentrant returns (bool) {
        if (_betID == 0 || _betID > betID) {
            revert InvalidBetID();
        }
        if (ReceiptInfo[_betID].player != msg.sender) {
            revert BetIDNotOwnedByMsgSender();
        }
         if (ReceiptInfo[_betID].lowPrizeRedeemStatus = 0 && ReceiptInfo[_betID].highPrizeRedeemStatus = 0) {
            revert BetIDAlreadyRedeemed();
        }

        uint256 price = getTicketPrice(_round);
        uint256 lv1;
        uint256 lv2;
        uint256 lv3;
        uint256 lv4;
        uint256 lv5;
        if (ReceiptInfo[_betID].lowPrizeRedeemStatus = 0 ) {
            lv3 += ReceiptInfo[_betID].lv3Prize;
            lv4 += ReceiptInfo[_betID].lv4Prize;
            lv5 += ReceiptInfo[_betID].lv5Prize;
        }
        if (ReceiptInfo[_betID].highPrizeRedeemStatus = 0 ) {
            lv1 += ReceiptInfo[_betID].lv1Prize;
            lv2 += ReceiptInfo[_betID].lv2Prize;
        }

        uint256 lowPrizePayment = (lv3 * 200 + lv4 * 20 + lv5 * 10) * price;

        if (lowPrizePayment > 0 && lowPrizePayment < lowPrizeReserves) {
            lowPrizeReserves -= lowPrizePayment_;
            ReceiptInfo[_betID].lowPrizeRedeemStatus = uint8(1);
            payable(msg.sender).transfer(lowPrizePayment);
            emit lowPrizeRedeemedByRound(msg.sender,lowPrizePayment,_round);
        } 
        
        if (lv1 > 0) {
            lv1Payment = lv1 * LotteryResult[_round].lv1Prize;
        }
        if (lv2 > 0) {
            lv2Payment = lv2 * LotteryResult[_round].lv2Prize;
        }
         uint256 highPrizePayment = lv1Payment + lv2Payment;

        if (highPrizePayment > 0 && highPrizePayment < highPrizeReserves) {
            highPrizeReserves -= highPrizePayment;
            ReceiptInfo[_betID].highPrizeRedeemStatus = uint8(1);
            payable(msg.sender).transfer(highPrizePayment);
            emit highPrizeRedeemedByRound(msg.sender,highPrizePayment,_round);
        }

        return true;
    }

    function deletePlayerRecord(uint256 _round) external nonReentrant returns (bool) {
        uint256 length = playerRecord[msg.sender][_round].length;
        if (length  == 0) {
            revert PlayerHasNoBettingRecord();
        }
        for (uint256 i = 0; i < length ; ++i) {
            uint256 _betID = playerRecord[msg.sender][_round][i];
            if (ReceiptInfo[_betID].lowPrizeRedeemStatus + ReceiptInfo[_betID].highPrizeRedeemStatus = 2) {
                delete ReceiptInfo[_betID];   
                delete playerRecord[msg.sender][_round][i];
            }
        }
        emit playerRecordDeletedByRound(msg.sender,_round);
        return true;

    }

        


    function getTicketPrice(uint256 _round) public view returns (uint256) {
        uint256 length = PriceHistory.length;
        uint256 ticketPrice_ ;
        if (_round >= PriceHistory[length-1][1]) {
                ticketPrice_ = PriceHistory[length-1][0];
        }
        
        for (uint256 i = 1 ; i < length; ++i) {
            if (_round < PriceHistory[i][1] && _round >= PriceHistory[i-1][1]) {
            ticketPrice_ = PriceHistory[i-1][0];
            }
        }
        return ticketPrice_ ;
    }



    /*//////////////////////////////////////////////////////////////
                            MANAGER FUNCTIONS 
    //////////////////////////////////////////////////////////////*/

    function setTicketPrice(uint256 _round, uint256 _price) public onlyOwner {
        PriceHistory.push([uint128(_price),uint128(_round)]);
    }
    

    /// disable directly ownership transfer
    function transferOwnership(address newOwner) public payable override  onlyOwner {
    }
    /// disable  renounceOwnership , this contract need manage 
    function renounceOwnership() public payable override onlyOwner {
    }


    /*//////////////////////////////////////////////////////////////
                            PURE FUNCTIONS 
    //////////////////////////////////////////////////////////////*/

    function FisherYatesShuffle(uint256[5] memory _fiveRandom) public pure returns (uint256[5] memory) {
        // 使用Fisher-Yates shuffle算法生成5个不同的随机值
        uint256[16] memory indices;
        for (uint8 i = 0; i < 16; i++) {
            indices[i] = i + 1;
        }
        for (uint256 i = 15; i > 10; i--) {
            uint256 j = uint256(_fiveRandom[i - 11] % (i + 1));
            uint256 temp = indices[i];
            indices[i] = indices[j];
            indices[j] = temp;
        }
        // 从1-16中选择5个不同的数字
        uint256[5] memory numbers;
        for (uint256 i = 0; i < 5; i++) {
            numbers[i] = indices[i + 11];
        }
        return numbers;
    }



    function insertionSort(uint256[5] memory _array) public pure returns(uint256[5] memory) {
        // note that uint can not take negative value
        for (uint i = 1;i < 5 ;i++){
            uint temp = _array[i];
            uint j=i;
            while( (j >= 1) && (temp < _array[j-1])){
                _array[j] = _array[j-1];
                j--;
            }
            _array[j] = temp;
        }
        return(_array);
    }

    /// copy from https://github.com/estarriolvetch/solidity-bits/blob/main/contracts/Popcount.sol
    function popcount256B(uint256 x) public pure returns (uint256) {
        if (x == type(uint256).max) {
            return 256;
        }
        unchecked {
            x -= (x >> 1) & m1;             //put count of each 2 bits into those 2 bits
            x = (x & m2) + ((x >> 2) & m2); //put count of each 4 bits into those 4 bits 
            x = (x + (x >> 4)) & m4;        //put count of each 8 bits into those 8 bits 
            x = (x * h01) >> 248;  //returns left 8 bits of x + (x<<8) + (x<<16) + (x<<24) + ... 
        }
        return x;
    }

    function NumberCount(uint256 _five, uint256 _one) public view  returns (uint256[2] memory) {
        uint256 out[4];
        uint16 five = lotteryResult.fiveBall ;
        uint16 one = lotteryResult.oneBall ;
        
        out[0] = popcount256B(_five)
        out[1] = popcount256B(_one)
        uint256 resultFive = uint16(_five) & five;
        out[2] = popcount256B(resultFive);
        uint256 resultOne = uint16(_one) & one;
        out[3]= popcount256B(resultOne);
        
        return out;
    }


}