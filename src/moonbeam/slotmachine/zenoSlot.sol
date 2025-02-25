// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC4626} from "solady/tokens/ERC4626.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
contract ZSM is ERC4626,IERC20 {

    /*//////////////////////////////////////////////////////////////
                            VIRARIABLES 
    //////////////////////////////////////////////////////////////*/

    /// @dev The main contract ZOM address 需要修改
    /// @notice 
    address public constant zomAddress = 0x0;

    /// @dev The address of the WGLMR contract
    /// from https://moonbeam.moonscan.io/token/0xacc15dc74880c9944775448304b263d191c6077f#tokenInfo
    address public constant wglmr = 0xAcc15dC74880C9944775448304B263D191c6077F;
    uint256 public exitFee ;

    /// @dev The number of play nonces.
    uint256 playNonces;
    mapping(uint256 => uint256) public playRecode;
    mapping(address => uint256) public claimablePrizes;


    /*//////////////////////////////////////////////////////////////
                           EVENTS & CUSTOM ERRORS 
    //////////////////////////////////////////////////////////////*/
    
    event Result(address indexed from,uint8[3][] indexed result, uint256 bonus);
    event RequestedArray(bytes32 indexed requestId, uint256 size);
    event ReceivedArray(bytes32 indexed requestId, uint16[16] response);


    /// @dev Cannot deposit more than the max limit.
    error MustGreaterThanZero();
    error MustLessThanOneTenthOfTotalassets();
    error MaximumBetAmountExceeded();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(uint256 _exitFee) {
        exitFee = _exitFee;
    }

    /*//////////////////////////////////////////////////////////////
                            VAULT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// use to collect the fees from other contracts
    receive() external payable {
        // 代码
    }

    function asset() public view override returns (address){
        return address(weth);
    }

    function name() public pure override returns (string memory) {
        return "Zeno slotmachine moonbeam";
    }

    function symbol() public pure override returns (string memory) {
        return "ZslotM";
    }

    // 4626 returns total number of assets
    function totalAssets() public view override returns (uint256) {
        //return address(this).balance + asset.balanceOf(address(this));
    return address(weth).balanceOf(address(this)) ; // weth + eth 总资产
    } 

     function _decimalsOffset() internal view override returns (uint8) {
        return 3; //初始的价格精度 
    }

    // 支付fee 到 zom
    function sendFees() public view  returns () {
        avalaibleFees = address(this).balance - 1000 ether; // 为系统保留gas
        if (avalaibleFees < 0) {}
        if (avalaibleFees > 1000 ether) {
            (bool success, ) = zomAddress.call{value: avalaibleFees}("");
            if (!success) revert feesSendFailed();
        }
    }

    function deposit(address to) public override returns (uint256 shares) {
        if (msg.value <= 0) {
            revert MustGreaterThanZero();
        }
        uint256 assets = msg.value;
        if (assets > maxDeposit(to)) _revert(0xb3c61a83); // `DepositMoreThanMax()`.
        shares = previewDeposit(assets);
        _deposit(msg.sender, to, assets, shares);
    }

    function _deposit(address by,address to, uint256 assets, uint256 shares) internal override {
        weth.deposit{ value: assets }();
        _mint(to, shares);
        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Deposit} event.
            mstore(0x00, assets)
            mstore(0x20, shares)
            let m := shr(96, not(0))
            log3(0x00, 0x40, _DEPOSIT_EVENT_SIGNATURE, and(m, by), and(m, to))
        }
        _afterDeposit(assets, shares);
    }

    function mint(uint256 shares, address to) 
        public 
        override 
        returns(uint256 assets) {
        }

    function withdraw(uint256 assets, address to, address owner)
        public
        override
        returns (uint256 shares){
    }

    function redeem(uint256 shares, address to, address owner)
        public
        virtual
        returns (uint256 assets){
        if (shares > maxRedeem(owner)) _revert(0x4656425a); // `RedeemMoreThanMax()`.
        assets = previewRedeem(shares);
        _withdraw(msg.sender, to, msg.sender, assets, shares);
    }
    }

    // 关闭ERC20的permit2
    function _spendAllowance(address owner, address spender, uint256 amount) internal override {}

    function _withdraw(address by, address to, address owner, uint256 assets, uint256 shares)
        internal
        verride
    {
        _beforeWithdraw(assets, shares);
        _burn(owner, shares);
        weth.withdraw(assets)
         (bool success, ) = to.call{value: assets}("");
        if (!success) revert withdrawSendFailed();

        /// @solidity memory-safe-assembly
        assembly {
            // Emit the {Withdraw} event.
            mstore(0x00, assets)
            mstore(0x20, shares)
            let m := shr(96, not(0))
            log4(0x00, 0x40, _WITHDRAW_EVENT_SIGNATURE, and(m, by), and(m, to), and(m, owner))
        }
    }





    // 关闭previewWithdraw
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
    }

    /// @dev Preview taking an exit fee on redeem. See {IERC4626-previewRedeem}.
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        uint256 assets = super.previewRedeem(shares);
        return assets - feeCaculator(assets);
    }

    function feeCaculator(uint256 assets) public view virtual override returns (uint256) {
        return  assets * exitFee / 10000;

    }


    /*//////////////////////////////////////////////////////////////
                            SLOTMACHINE LOGIC
    //////////////////////////////////////////////////////////////*/

    
    function insertionSort(uint256[3] memory a) public pure returns(uint256[] memory) {
        // note that uint can not take negative value
        for (uint i = 1;i < 3 ;i++){
            uint temp = a[i];
            uint j=i;
            while( (j >= 1) && (temp < a[j-1])){
                a[j] = a[j-1];
                j--;
            }
            a[j] = temp;
        }
        return(a);
    }

    function bet(uint256 _betAmount,uint256 times) public returns (bool) {
        if  (_betAmount <= 0) 
            revert MustGreaterThanZero(); // 使用 _revert(byte4)  函数签名
        if  (_betAmount > type(uinit88).max) 
            revert MaximumBetAmountExceeded();
        if  (betAmount > totalAssets()/1000) 
            revert MustLessThanOneTenthOfTotalassets();
        if (times > 11 &&  times < 1) 
            revert BatchBetMustBeFewerThanTenTimes();
        if (times= 1) {singleBet(_betAmount)
        } else {batchBet(_betAmount,times)};

        ++playNonces;
        playRecode[playNonces] = uint160(msg.sender) << 96 | uint88(_betAmount) << 8 | uint8(1);
        callRandom(3);
        return ture;
    }

     //单次下注
    function multiBet(uint256 _betAmount,uint256 times) public returns (bool) {
        ++playNonces;
        playRecode[playNonces] = uint160(msg.sender) << 96 | uint88(_betAmount) << 8 | uint8(times);
        callRandom(3*times);
        return ture;
    }

    function singleBet(uint256 _betAmount) public returns (bool) {
        ++playNonces;
        playRecode[playNonces] = uint160(msg.sender) << 96 | uint88(_betAmount) << 8 | uint8(1);
        callRandom(playNonces,3);
        return ture;
    }

    function callRandom(uint256 memory playNonces,uint256 memory amount) public returns (uint256[] memory randomArray) {
     
    }

    function executeRandom(uint256 calldata playNonces,uint256 calldata _betAmount,uint256[] calldata randomArray) public returns (uint256[] memory) {
        convertTo2DArray(randomArray);


    }


    function spinReels(uint256 calldata _betAmount,uint256[3] calldata randomArray) public returns (uint256 memory Prize) {
        uint256 prizeMultiplier;
        uint256 prize;
        uint256[3] sortedArray ;
        uint256[3] slot ;
        = insertionSort(randomArray);
        for (uint i = 0; i < 3; i++) {
           slot[i] = sortedArray[i] % 7
        }

        if (slot[0] == slot[1] && slot[1] == slot[2] && slot[0] == 1) {
            prizeMultiplier = 100;
        } 
        if (slot[0] == slot[1] && slot[1] == slot[2] && slot[0] == 2) {
            prizeMultiplier = 25;
        } 
     
        if (slot[0] == slot[1] && slot[1] == slot[2] && slot[0] == 3) {
            prizeMultiplier = 20;
        } 
        if (slot[0] == slot[1] && slot[1] == slot[2] && slot[0] == 4) {
            prizeMultiplier = 15;
        }
        if (slot[0] == slot[1] && slot[1] == slot[2] && slot[0] == 5) {
            prizeMultiplier = 10;
        }
        if (slot[0] == slot[1] && slot[1] == slot[2] && slot[0] == 6) {
            prizeMultiplier = 5;
        }
        if (slot[0] == slot[1] && slot[1] == slot[2] && slot[0] == 7) {
            prizeMultiplier = 3;
        }
        if (slot[0] == slot[1] && slot[1] != slot[2]) {
            prizeMultiplier = 2;
        }
        if (slot[0] != slot[1] && slot[1] == slot[2]) {
            prizeMultiplier = 1;
        } else {
            prizeMultiplier = 0;
        }
        prize = _betAmount * prizeMultiplier;
        return (slot,  prize);
    }


    /*//////////////////////////////////////////////////////////////
                            PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function convertTo2DArray(uint[] memory inputArray) public pure returns (uint[3][] memory) {
        // 计算可以形成的子数组数量
        uint numRows = inputArray.length / 3; 
        uint[3][] memory result = new uint[3][](numRows); // 创建二维数组

        // 填充二维数组
        for (uint i = 0; i < inputArray.length; i++) {
            uint row = i / 3; // 当前行索引
            uint col = i % 3; // 当前列索引
            result[row][col] = inputArray[i]; // 填充元素
        }

        return result; // 返回结果
    }

    function insertionSort(uint256[3] memory a) public pure returns(uint256[3] memory) {
        // note that uint can not take negative value
        for (uint i = 1;i < 3 ;i++){
            uint temp = a[i];
            uint j=i;
            while( (j >= 1) && (temp < a[j-1])){
                a[j] = a[j-1];
                j--;
            }
            a[j] = temp;
        }
        return(a);
    }



}