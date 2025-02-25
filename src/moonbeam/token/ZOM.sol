// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20Votes} from "solady-0.0.265/tokens/ERC20Votes.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-contracts-5.1.0/utils/ReentrancyGuardTransient.sol";
import {INANFT} from "../interfaces/INANFT.sol";

contract ZOM is ERC20Votes, ReentrancyGuardTransient {
    /*//////////////////////////////////////////////////////////////
                              CONSTANTS  
    //////////////////////////////////////////////////////////////*/

    address public immutable nftAddress;
    uint256 private immutable deployTime;
    address private immutable teamAddress;

    /*//////////////////////////////////////////////////////////////
                              CUSTOM ERRORS  
    //////////////////////////////////////////////////////////////*/

    error OnlyNovationAgreementContract();
    error NotAllowedZeroAddress();
    error InsufficientFunds();
    error ExceedMaxSupply();
    error PaymentTransferFailed();
    error InsufficientZOMBalance();
    error NotOwnerOfTheNFT();
    error CanNotReceivePaymentsWithUnknownCalldata();


    /*//////////////////////////////////////////////////////////////
                                EVENTS 
    //////////////////////////////////////////////////////////////*/
    event TokenMinted(address indexed to, uint256 indexed amount);
    event PledgeSuccess(
        address indexed borrower,
        uint256 collateral,
        uint256 indexed loanAmount,
        uint256 timeStamp,
        uint256 indexed tokenId
    );
    event RedeemSuccess(
        address indexed borrower,
        uint256 repayment,
        uint256 indexed redeemAmount,
        uint256 indexed tokenId
    );
    event DonationReceived(
        address indexed donor, 
        uint256 indexed amount
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE 
    //////////////////////////////////////////////////////////////*/


    uint128 public loansBalance;
    uint128 public collateralBalance;
    mapping(address => uint256) public collateralByAddress;
    mapping(uint256 => uint256) public collateralById;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _nftAddress) {
        teamAddress = msg.sender;
        deployTime = block.timestamp;
        nftAddress = _nftAddress;
    }

    fallback() external payable {
        revert CanNotReceivePaymentsWithUnknownCalldata();
    }

    receive () external payable {
        donate();
    }

    function donate() internal nonReentrant returns (bool) {
        emit DonationReceived(msg.sender, msg.value);
        return true;
    }

    modifier onlyNft() {
        if (msg.sender != nftAddress) {
            revert OnlyNovationAgreementContract();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC20
    //////////////////////////////////////////////////////////////*/
    function name() public pure override returns (string memory) {
        return "Zeno of Moonbeam";
    }

    function symbol() public pure override returns (string memory) {
        return "ZOM";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    // max=1_000_000_000*10**18
    function maxSupply() public pure returns (uint256) {
        return 1e27;
    }

    function increaseAllowance(address spender, uint256 amount)
        public
        nonReentrant
        returns (bool)
    {
        if (spender == address(0)) {
            revert NotAllowedZeroAddress();
        }
        uint256 prevAllowance = allowance(msg.sender, spender);
        uint256 balanceOfOwner = balanceOf(msg.sender);
        uint256 newAllowance = prevAllowance + amount;
        if (newAllowance > balanceOfOwner) {
            newAllowance = balanceOfOwner;
        } 
        assembly {
            // Compute the allowance slot and store the amount.
            mstore(0x20, spender)
            mstore(0x0c, 0x7f5e9f20) // solady erc20 uint256 private constant _ALLOWANCE_SLOT_SEED = 0x7f5e9f20;
            mstore(0x00, caller())
            sstore(keccak256(0x0c, 0x34), newAllowance)
            // Emit the {Approval} event.
            mstore(0x00, newAllowance)
            // `keccak256(bytes("Approval(address,address,uint256)"))
            // private constant _APPROVAL_EVENT_SIGNATURE =0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
            log3(
                0x00,
                0x20,
                0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925,
                caller(),
                shr(96, mload(0x2c))
            )
        }
        return true;
    }

    function decreaseAllowance(address spender, uint256 amount)
        public
        nonReentrant
        returns (bool)
    {
        if (spender == address(0)) {
            revert NotAllowedZeroAddress();
        }
        uint256 prevAllowance = allowance(msg.sender, spender);
        uint256 newAllowance;
        if (prevAllowance < amount) {
            newAllowance = 0;
        } else {
            newAllowance = prevAllowance - amount;
        }
        assembly {
            // Compute the allowance slot and store the amount.
            mstore(0x20, spender)
            mstore(0x0c, 0x7f5e9f20) // _ALLOWANCE_SLOT_SEED = 0x7f5e9f20
            mstore(0x00, caller())
            sstore(keccak256(0x0c, 0x34), newAllowance)
            // Emit the {Approval} event.
            mstore(0x00, newAllowance)
            log3(
                0x00,
                0x20,
                0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925,
                caller(),
                shr(96, mload(0x2c))
            )
        }
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                              EIP2612
    //////////////////////////////////////////////////////////////*/
    function _versionHash() internal view override returns (bytes32 result) {}

    function _incrementNonce(address owner) internal override {}

    function nonces(address owner)
        public
        view
        override
        returns (uint256 result)
    {}

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {}

    function DOMAIN_SEPARATOR() public view override returns (bytes32 result) {}

    /*//////////////////////////////////////////////////////////////
                              EIP5805
    //////////////////////////////////////////////////////////////*/

    function _getVotingUnits(address delegator)
        internal
        view
        override
        returns (uint256)
    {
        return balanceOf(delegator) + collateralByAddress[delegator];
    }

    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override {}

    function tokenOfferingPrice()
        public
        view
        returns (uint256)
    {
        uint256 daysElapsed = (block.timestamp - deployTime) / 1 days;
        uint256 newPrice = (1 ether + 0.001 ether * daysElapsed) / 20;
        return newPrice;
    }

    function vaultBalance() public view  returns (uint256) {
        return address(this).balance;
    }

    function mint() external payable nonReentrant returns (bool) {
        if (msg.value == 0) {
            revert InsufficientFunds();
        }
        uint256 amountToMint = (msg.value / tokenOfferingPrice()) * 1e18;
        if ((totalSupply() + (amountToMint * 10) / 9) > maxSupply()) {
            revert ExceedMaxSupply();
        }

        uint256 teamToken = amountToMint / 9;
        _mint(teamAddress, teamToken);

        uint256 teamAmount = msg.value / 10;
        (bool success, ) = payable(teamAddress).call{value: teamAmount, gas: 0}(
            ""
        );
        if (!success) {
            revert PaymentTransferFailed();
        }

        _mint(msg.sender, amountToMint);
        emit TokenMinted(msg.sender, amountToMint);
        return true;
    }

    function creditLine(uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 totalLiudity = vaultBalance() + loansBalance;
        uint256 loanAmount = (amount * totalLiudity * 95) /
            (totalSupply() * 100);
        return loanAmount;
    }

    function pledge(uint256 amount) external nonReentrant returns (bool) {
        if (balanceOf(msg.sender) < amount) {
            revert InsufficientZOMBalance();
        }
        // Calculate the amount of Ether the user can receive
        uint256 loanAmount = creditLine(amount);
        loansBalance += uint128(loanAmount);
        collateralBalance += uint128(amount);
        collateralByAddress[msg.sender] += amount;
        // Transfer the ZOM tokens from the user to the contract
        transferFrom(msg.sender, address(this), amount);
        // Transfer the calculated Ether to the user

        // mint novation agreement nft for the user
        uint256 tokenId = INANFT(nftAddress).mint(
            msg.sender,
            amount,
            loanAmount,
            block.timestamp
        );
        collateralById[tokenId] = amount;

        /// finally pay ether to user
        (bool success, ) = payable(msg.sender).call{
            value: loanAmount,
            gas: 2300
        }("");
        if (!success) {
            revert PaymentTransferFailed();
        }

        emit PledgeSuccess(
            msg.sender,
            amount,
            loanAmount,
            block.timestamp,
            tokenId
        );
        return true;
    }

    function redeem(uint256 tokenId)
        external
        payable
        nonReentrant
        returns (bool)
    {
        if (INANFT(nftAddress).ownerOf(tokenId) != msg.sender) {
            revert NotOwnerOfTheNFT();
        }
        (uint256 collateral, uint256 loanAmount, uint256 issuanceTime) = INANFT(
            nftAddress
        ).note(tokenId);

        uint256 daysElapsed = (block.timestamp - issuanceTime) / 1 days;
        uint256 interestAmount = (loanAmount * daysElapsed) / 20000;
        uint256 totalRepayment = loanAmount + interestAmount;

        if (msg.value < totalRepayment) {
            revert InsufficientFunds();
        }
        loansBalance -= uint128(loanAmount);
        collateralBalance -= uint128(collateral); //
        collateralByAddress[msg.sender] -= collateral;
        collateralById[tokenId] = 0;
        INANFT(nftAddress).burn(tokenId);

        /// finally tansfer zom to user
        transfer(msg.sender, collateral);
        emit RedeemSuccess(msg.sender, totalRepayment, collateral, tokenId);
        return true;
    }

    function redeemPaymentCaculate(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        (uint256 collateral, uint256 loanAmount, uint256 issuanceTime) = INANFT(
            nftAddress
        ).note(tokenId);
        collateral = collateral;
        uint256 daysElapsed = (block.timestamp - issuanceTime) / 1 days;
        uint256 interestAmount = (loanAmount * daysElapsed) / 20000;
        uint256 totalRepayment = loanAmount + interestAmount;
        return totalRepayment;
    }

    function transfercollateral(
        address from,
        address to,
        uint256 amount
    ) external onlyNft {
        collateralByAddress[from] -= amount;
        collateralByAddress[to] += amount;
    }
}
