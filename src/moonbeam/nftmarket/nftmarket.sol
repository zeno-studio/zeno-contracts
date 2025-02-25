//SPDX-License-Identifier: MIT
pragma solidity  0.8.28;

import {Ownable} from "solady-0.0.265/auth/Ownable.sol";
import {ReentrancyGuardTransient} from "solady-0.0.265/utils/ReentrancyGuardTransient.sol";
import {BitMaps} from "@openzeppelin-contracts-5.1.0/utils/structs/BitMaps.sol";
import {IERC721} from "@openzeppelin-contracts-5.1.0/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin-contracts-5.1.0/utils/introspection/IERC165.sol";


contract ZenoNFTMarket is Ownable, ReentrancyGuardTransient {
    using BitMaps for BitMaps.BitMap;

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS  
    //////////////////////////////////////////////////////////////*/

     // Replace with the address of the fee receiver contract
    address immutable _FEE_RECEIVER;
    
    uint256 constant _MAX_PRICE = type(uint128).max;
    uint256 constant _MAX_TIME = type(uint40).max;
    uint256 constant _MAX_TOKEN_ID = type(uint96).max;
    bytes4 constant _ERC165ID = 0x01ffc9a7;
    bytes4 constant _ERC721ID = 0x80ac58cd;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS 
    //////////////////////////////////////////////////////////////*/
    error CanNotReceivePaymentsWithEmptyCalldata();
    error CanNotReceivePaymentsWithUnknownCalldata();
    error TokenIdMustBeLessThanMaxTokenId();
    error EndPriceMustBeLessThanStartPrice();
    error OfferPriceMustBeGreatThanZero();
    error OfferPriceMustBeLessThanMAXPRICE();
    error DailyDiscountMustBeLessThanPriceDifference();
    error NFTContractMustSupportERC721();
    error NFTNotOwnedByMsgSender();
    error NFTNotApproved();
    error InvalidOfferId();
    error NotCorrectOfferer();
    error CurrentOfferAlreadyClosed();
    error DutchAuctionCannotChangePrice();
    error OfferPriceMustBeLessThanCurrentBidPrice();
    error InvalidBidId();
    error InsufficientFunds();
    error DutchAuctionCannotBid();
    error BidPriceMustBeLessThanCurrentOfferPrice();
    error BidPriceMustBeGreatThanPrevBidPrice();
    error NotCorrectBidder();
    error CurrentBidAlreadyClosed();
    error OfferPriceMustBeGreatThanCurrentBidPrice();
    error BidCanOnlyCancelAfterOneDay();
    error EmptyPoolOfFee();
    error LowBalanceForFeeTransfer();


    /*//////////////////////////////////////////////////////////////
                                EVENTS 
    //////////////////////////////////////////////////////////////*/

    event DutchAuctionListed(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 startPrice,
        uint256 endPrice,
        uint256 startTime,
        uint256 dailyDiscount,
        uint256 offerId
    );
    event StandardAuctionListed(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 startPrice,
        uint256 offerId
    );
    event OfferCanceled(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 offerId
    );
    event OfferPriceChanged(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 newPrice,
        uint256 offerId
    );
    event SellerAcceptedBid(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 BidPrice,
        uint256 offerId,
        uint256 bidId
    );
    event BidListed(
        address indexed seller,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 bidPrice,
        uint256 offerId,
        uint256 bidId
    );

    event BidPriceChanged(
        address indexed buyer,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 newPrice,
        uint256 bidId
    );
    event BuyerAcceptedOffer(
        address indexed buyer,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 offerPrice,
        address seller,
        uint256 offerId
    );
    event BidCanceled(
        address indexed buyer,
        address indexed nft,
        uint256 indexed tokenId,
        uint256 offerId,
        uint256 bidId
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE 
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct is packed to fit within tree 256-bit slot
    /// @dev uint64 has max value 1.8e19, or 18 ether
    struct OfferTicket {
        address seller;
        uint40 startTime;
        uint8 offerMethod; // (0:standard, 1:dutch)
        uint128 offerPrice;
        uint128 currentBidId;
        address nft;
        uint96 tokenId;
    }

    /// @notice Struct is packed to fit within a two 256-bit slot

    struct DutchAuctionParams {
        uint128 endPrice;
        uint128 dailyDiscount; // pricediscount per day
    }

    struct BidTicket {
        address buyer;
        uint40 bidTime;
        uint128 bidPrice;
        uint128 offerId;
    }

    uint128 public offerId;
    uint128 public bidId;
    uint128 public feeBasePoint = 50;
    uint128 public poolOfFee;

    mapping(uint256 => OfferTicket) public offerIdInfo; // mapping of offerId to offerIdInfo
    mapping(uint256 => DutchAuctionParams) public dutchAuctionParams; // mapping of offerId to dutchAuctionParams
    mapping(uint256 => BidTicket) public bidIdInfo;
    BitMaps.BitMap private offerClosed;
    BitMaps.BitMap private bidClosed;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address ZenoTokenAddress) {
        _FEE_RECEIVER = ZenoTokenAddress;
        _initializeOwner(msg.sender);
        
    }

    receive () external payable {
        revert CanNotReceivePaymentsWithEmptyCalldata();
    }

    fallback() external payable {
        revert CanNotReceivePaymentsWithUnknownCalldata();
    }

    /*//////////////////////////////////////////////////////////////
                             AUCTION LOGIC 
    //////////////////////////////////////////////////////////////*/


    /// @dev 
    /// dicounting must last at least 1 days
    /// offerer need not pay platform fee at listing 
    /// offerer need to pay platform fee at AcceptBid (price - fee)

    function dutchAuctionList(
        address _nft,
        uint256 _tokenId,
        uint256 _startprice,
        uint256 _endprice,
        uint256 _dailyDiscount
    ) external payable nonReentrant returns (bool) {
        /// parameter check
        if (_tokenId > _MAX_TOKEN_ID) {
            revert TokenIdMustBeLessThanMaxTokenId();
        }
        if (_endprice >= _startprice) {
            revert EndPriceMustBeLessThanStartPrice();
        }
        if (_startprice == 0) {
            revert OfferPriceMustBeGreatThanZero();
        }
        if (_startprice > _MAX_PRICE) {
            revert OfferPriceMustBeLessThanMAXPRICE();
        }
        
        if (_dailyDiscount > (_startprice - _endprice)) {
            revert DailyDiscountMustBeLessThanPriceDifference();
        }

        // ERC721 check
        IERC721 nftContract = IERC721(_nft);
        bool isERC721 = IERC165(nftContract).supportsInterface(0x80ac58cd);
        if (!isERC721) {
            revert NFTContractMustSupportERC721();
        }
        /// nft owner check
        bool isOwner = nftContract.ownerOf(_tokenId) == msg.sender;
        if (!isOwner) {
            revert NFTNotOwnedByMsgSender();
        }

        /// approval and approval for all check
        bool isIndividuallyApproved = nftContract.getApproved(_tokenId) ==
            address(this);
        bool isApprovedForAll = nftContract.isApprovedForAll(
            msg.sender,
            address(this)
        );
        if (!isIndividuallyApproved && !isApprovedForAll) {
            revert NFTNotApproved();
        }

        /// transfer NFT From offerer to contract
        nftContract.transferFrom(msg.sender, address(this), _tokenId);
        /// ID increment
        ++offerId;
        uint128 offerId_ = offerId;
        uint40 startTime_ = uint40(block.timestamp);

        /// offer Info update
        offerIdInfo[offerId_] = OfferTicket({
            seller: msg.sender,
            startTime: startTime_,
            offerMethod: uint8(1),
            offerPrice: uint128(_startprice),
            currentBidId: uint128(0),
            nft: _nft,
            tokenId: uint96(_tokenId)
        });
        dutchAuctionParams[offerId_] = DutchAuctionParams({
            endPrice: uint128(_endprice),
            dailyDiscount: uint128(_dailyDiscount)
        });

        emit DutchAuctionListed(
            msg.sender,
            _nft,
            _tokenId,
            _startprice,
            _endprice,
            startTime_,
            _dailyDiscount,
            offerId_
        );
        return true;
    }


    function standardAuctionList(
        address _nft,
        uint256 _tokenId,
        uint256 _startprice
    ) external payable nonReentrant returns (bool) {
        /// parameter check
        if (_tokenId > _MAX_TOKEN_ID) {
            revert TokenIdMustBeLessThanMaxTokenId();
        }
        if (_startprice == 0) {
            revert OfferPriceMustBeGreatThanZero();
        }
        if (_startprice > _MAX_PRICE) {
            revert OfferPriceMustBeLessThanMAXPRICE();
        }

        /// ERC721 check
        IERC721 nftContract = IERC721(_nft);
        bool isERC721 = IERC165(nftContract).supportsInterface(_ERC721ID);
        if (!isERC721) {
            revert NFTContractMustSupportERC721();
        }

        /// nft owner check
        bool isOwner = nftContract.ownerOf(_tokenId) == msg.sender;
        if (!isOwner) {
            revert NFTNotOwnedByMsgSender();
        }
        /// approval and approval for all check
        bool isIndividuallyApproved = nftContract.getApproved(_tokenId) ==
            address(this);
        bool isApprovedForAll = nftContract.isApprovedForAll(
            msg.sender,
            address(this)
        );
        if (!isIndividuallyApproved && !isApprovedForAll) {
            revert NFTNotApproved();
        }

        /// transfer NFT From offerer to contract
        nftContract.transferFrom(msg.sender, address(this), _tokenId);
        /// ID increment
        ++offerId;
        uint256 offerId_ = offerId;

        offerIdInfo[offerId_] = OfferTicket({
            seller: msg.sender,
            startTime: uint40(block.timestamp),
            offerMethod: uint8(1),
            offerPrice: uint128(_startprice),
            currentBidId: uint128(0),
            nft: _nft,
            tokenId: uint96(_tokenId)
        });

        // emit the NFTListed event
        emit StandardAuctionListed(
            msg.sender,
            _nft,
            _tokenId,
            _startprice,
            offerId_
        );
        return true;
    }

    function cancelOffer(uint256 _offerId)
        external
        payable
        nonReentrant
        returns (bool)
    {
        /// check if offer exists
        if (_offerId > offerId) {
            revert InvalidOfferId();
        }
        /// check if offer is Correct offerer
        if (offerIdInfo[_offerId].seller != msg.sender) {
            revert NotCorrectOfferer();
        }
        /// check if offer is active
        if (offerClosed.get(_offerId)) {
            revert CurrentOfferAlreadyClosed();
        }

        /// read offer info
        address nftAddress_ = offerIdInfo[_offerId].nft;
        uint256 tokenId_ = offerIdInfo[_offerId].tokenId;
        address owner = offerIdInfo[_offerId].seller;

        /// transfer NFT From contract to offerer
        IERC721(nftAddress_).transferFrom(address(this), owner, tokenId_);
        
        /// delete dutchAuctionParams
        if (offerIdInfo[_offerId].offerMethod == 1) {
            delete dutchAuctionParams[_offerId];
        }
        /// delete offer Info by id
        delete offerIdInfo[_offerId];

        /// set offer as closed
        offerClosed.set(_offerId);

        emit OfferCanceled(msg.sender, nftAddress_, tokenId_, _offerId);

        return true;
    }


    function changeOfferPrice(uint256 _offerId, uint256 _newPrice)
        external
        payable
        nonReentrant
        returns (bool)
    {
        /// check if offer exists
        if (_offerId > offerId) {
            revert InvalidOfferId();
        }
        /// check if offer is Correct offerer
        if (offerIdInfo[_offerId].seller != msg.sender) {
            revert NotCorrectOfferer();
        }
        /// check if offer is active
        if (offerClosed.get(_offerId)) {
            revert CurrentOfferAlreadyClosed();
        }
        /// check if dutchAuction?
        if (offerIdInfo[_offerId].offerMethod == 1) {
            revert DutchAuctionCannotChangePrice();
        }
        /// price param check
        if (_newPrice == 0) {
            revert OfferPriceMustBeGreatThanZero();
        }
        if (_newPrice > _MAX_PRICE) {
            revert OfferPriceMustBeLessThanMAXPRICE();
        }

        uint256 currentBidId = offerIdInfo[_offerId].currentBidId;

        /// check is a bid exists
        if (currentBidId == 0) {
            offerIdInfo[_offerId].offerPrice = uint128(_newPrice);
        } else {
            uint256 currentBidPrice = bidIdInfo[currentBidId].bidPrice;
        /// check if new price is less than current bid
            if (_newPrice >= currentBidPrice) {
                revert OfferPriceMustBeLessThanCurrentBidPrice();
            }
            offerIdInfo[_offerId].offerPrice = uint128(_newPrice);
        }

        /// read info for event
        address nft_ = offerIdInfo[_offerId].nft;
        uint256 tokenId_ = offerIdInfo[_offerId].tokenId;

        emit OfferPriceChanged(msg.sender, nft_, tokenId_, _newPrice, _offerId);

        return true;
    }

    function sellerAcceptBid(uint256 _offerId, uint256 _bidId)
        external
        payable
        nonReentrant
        returns (bool)
    {
        /// check is offerid valid?
        if (_offerId > offerId) {
            revert InvalidOfferId();
        }
        /// check is correct seller?
        if (offerIdInfo[_offerId].seller != msg.sender) {
            revert NotCorrectOfferer();
        }
        /// check is bid closed?
        if (offerClosed.get(_offerId)) {
            revert CurrentOfferAlreadyClosed();
        }
        /// check is correct bidid
        uint256 currentBidId_ = offerIdInfo[_offerId].currentBidId;
        if (currentBidId_ != _bidId) {
            revert InvalidBidId();
        }
        /// read bid info
        uint128 currentBidPrice_ = bidIdInfo[currentBidId_].bidPrice;
        address nft_ = offerIdInfo[_offerId].nft;
        uint96 tokenId_ = offerIdInfo[_offerId].tokenId;
        address buyer_ = bidIdInfo[_offerId].buyer;
        uint256 fee_ = (currentBidPrice_ * feeBasePoint) / 10000;

        /// update pool
        poolOfFee += uint128(fee_); 
         /// Transfer NFT to buer
        IERC721(nft_).safeTransferFrom(address(this), buyer_, tokenId_);
        /// transfer bid price-fee to seller
        payable(msg.sender).transfer(currentBidPrice_ - fee_);

        emit SellerAcceptedBid(
            msg.sender,
            nft_,
            tokenId_,
            currentBidPrice_,
            _offerId,
            _bidId
        );

        return true;
    }

    function standardAuctionBid(uint256 _offerId, uint256 _price)
        external
        payable
        nonReentrant
        returns (bool)
    {
        /// check params
        if (_price == 0) {
            revert OfferPriceMustBeGreatThanZero();
        }
        /// value = price 
        /// fee will be paid by taker so maker need deposit
        if (msg.value < _price ) {
            revert InsufficientFunds();
        }
        if (_offerId > offerId) {
            revert InvalidOfferId();
        }
        if (offerClosed.get(_offerId)) {
            revert CurrentOfferAlreadyClosed();
        }
        /// dutchAuction noly allow to aceept current price offer
        if (offerIdInfo[_offerId].offerMethod == 1) {
            revert DutchAuctionCannotBid();
        }
        
        /// if bid price great than current offer price , user need to use buyerAcceptOffer()
        /// aim to prevent user send wrong price tx
        uint256 currentOfferPrice_ = offerIdInfo[_offerId].offerPrice;
        if (_price >= currentOfferPrice_) {
            revert BidPriceMustBeLessThanCurrentOfferPrice();
        }

        /// check is previous bid exists 
        uint256 prevBidId_ = offerIdInfo[_offerId].currentBidId;
        ++bidId;
        uint256 bidId_ = bidId;
        if (prevBidId_ == 0) {
            ++bidId;
            offerIdInfo[_offerId].currentBidId = uint128(bidId_);
            bidIdInfo[bidId].buyer = msg.sender;
            bidIdInfo[bidId].bidTime = uint40(block.timestamp);
            bidIdInfo[bidId].bidPrice = uint128(_price);
            bidIdInfo[bidId].offerId = uint128(_offerId);
        } else {
            uint256 prevBidPrice_ = bidIdInfo[prevBidId_].bidPrice;

            if (_price <= prevBidPrice_ ) {
                revert BidPriceMustBeGreatThanPrevBidPrice();
            }
            if (_price > prevBidPrice_ ) {
                ++bidId;
                offerIdInfo[_offerId].currentBidId = uint128(bidId_);
                bidIdInfo[bidId].buyer = msg.sender;
                bidIdInfo[bidId].bidTime = uint40(block.timestamp);
                bidIdInfo[bidId].bidPrice = uint128(_price);
                bidIdInfo[bidId].offerId = uint128(_offerId);
                delete bidIdInfo[prevBidId_];
                /// pay back prev bidder's deposit 
                payable(bidIdInfo[prevBidId_].buyer).transfer(
                    prevBidPrice_
                );
            }
        }
        /// read info for event
        address nft_ = offerIdInfo[_offerId].nft;
        uint256 tokenId_ = offerIdInfo[_offerId].tokenId;

        emit BidListed(
            msg.sender,
            nft_,
            tokenId_,
            _price,
            _offerId,
            bidId_

        );
        return true;
    }

    function ChangeBidPrice(uint256 _bidId, uint256 _newPrice)
        external
        payable
        nonReentrant
        returns (bool)
    {

        /// check params
        if (_bidId > bidId) {
            revert InvalidBidId();
        }
        if (bidIdInfo[_bidId].buyer != msg.sender) {
            revert NotCorrectBidder();
        }

        if (bidClosed.get(_bidId)) {
            revert CurrentBidAlreadyClosed();
        }
        if (_newPrice == 0) {
            revert OfferPriceMustBeGreatThanZero();
        }
        if (_newPrice > _MAX_PRICE) {
            revert OfferPriceMustBeLessThanMAXPRICE();
        }
        
        /// user need add funds for new price
        uint256 prevBidPrice_ = bidIdInfo[_bidId].bidPrice;
        if (msg.value < _newPrice - prevBidPrice_) {
            revert InsufficientFunds();
        }
        if (_newPrice <= bidIdInfo[_bidId].bidPrice) {
            revert OfferPriceMustBeGreatThanCurrentBidPrice();
        }
        /// update bid price
        bidIdInfo[_bidId].bidPrice = uint128(_newPrice);

        /// read info for event
        address nft_ = offerIdInfo[bidIdInfo[_bidId].offerId].nft;
        uint256 tokenId_ = offerIdInfo[bidIdInfo[_bidId].offerId].tokenId;
        emit BidPriceChanged(msg.sender, nft_, tokenId_, _newPrice, _bidId);

        return true;
    }

    function cancelBid(uint256 _bidId)
        external
        payable
        nonReentrant
        returns (bool)
    {
        if (_bidId > bidId) {
            revert InvalidBidId();
        }
        if (bidClosed.get(_bidId)) {
            revert CurrentBidAlreadyClosed();
        }
        if (bidIdInfo[_bidId].buyer != msg.sender) {
            revert NotCorrectBidder();
        }
        if (block.timestamp - bidIdInfo[_bidId].bidTime < 1 days) {
            revert BidCanOnlyCancelAfterOneDay();
        }

        /// update bid info and offer info
        uint256 offerId_ = bidIdInfo[_bidId].offerId;
        address nft_ = offerIdInfo[offerId_].nft;
        uint256 tokenId_ = offerIdInfo[offerId_].tokenId;
        offerIdInfo[offerId_].currentBidId = uint128(0);
        bidClosed.set(_bidId);
        delete bidIdInfo[_bidId];

        /// pay back prev bidder's deposit 
        payable(bidIdInfo[_bidId].buyer).transfer(
            bidIdInfo[_bidId].bidPrice
        );
        
        emit BidCanceled(msg.sender, nft_, tokenId_,offerId_, _bidId);
        return true;

    }

    function buyerAcceptOffer(uint256 _offerId)
        external
        payable
        nonReentrant
        returns (bool)
    {
        /// check params
        if (_offerId > offerId) {
            revert InvalidOfferId();
        }
        if (offerClosed.get(_offerId)) {
            revert CurrentOfferAlreadyClosed();
        }
        /// taker pay platform fee check
        /// check is dutchAuction or standardAuction
        uint256 price_ ;
        if (offerIdInfo[_offerId].offerMethod == 1) {
            price_ = getDutchAuctionPrice(_offerId);
        } else {
            price_ = offerIdInfo[_offerId].offerPrice;
        }

        uint256 fee_ = (price_ * feeBasePoint) / 10000;

        if (msg.value < price_ + fee_) {
            revert InsufficientFunds();
        }


        address seller_ = offerIdInfo[_offerId].seller;
        address nft_ = offerIdInfo[_offerId].nft;
        uint256 tokenId_ = offerIdInfo[_offerId].tokenId;
        uint256 prevBidId_ = offerIdInfo[_offerId].currentBidId;   
        /// close previous bid if exists
        /// delete prev bid info
        /// paid back prev bidder deposit
        if (prevBidId_ != 0) {
            uint256 prevBidPrice_ = offerIdInfo[_offerId].offerPrice;
            address prevBuyer_ = bidIdInfo[prevBidId_].buyer;    
            delete bidIdInfo[prevBidId_];
            bidClosed.set(prevBidId_);
            payable(prevBuyer_).transfer(prevBidPrice_ );
        }

        /// delete offer info
        /// close offer
        poolOfFee += uint128(fee_); /// update pool of fee_;
        delete offerIdInfo[_offerId];
        offerClosed.set(_offerId);

        /// Transfer NFT to buyer
        IERC721(nft_).safeTransferFrom(address(this), msg.sender, tokenId_);
        /// Transfer price to seller
        payable(seller_).transfer(price_);

        emit BuyerAcceptedOffer(
            msg.sender,
            nft_,
            tokenId_,
            price_,
            seller_,
            _offerId
        );
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGER FUNCTIONS 
    //////////////////////////////////////////////////////////////*/

    /// disable directly ownership transfer
    function transferOwnership(address newOwner) public payable override  onlyOwner {
    }


    function changeFeeBasePoint(uint256 _newBasePoint)
        external
        nonReentrant
        onlyOwner
        returns (bool)
    {
        feeBasePoint = uint128(_newBasePoint);
        return true;
    }

    function sendFee()
        external
        nonReentrant
        returns (bool)
    {
        if (poolOfFee == 0) {
            revert EmptyPoolOfFee();
        }
        if (address(this).balance < poolOfFee - 1 ether) {
            revert LowBalanceForFeeTransfer();
        }
        payable(_FEE_RECEIVER).transfer(poolOfFee - 1 ether);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS 
    //////////////////////////////////////////////////////////////*/

    function getDutchAuctionPrice(uint256 _offerId)
        public
        view
        nonReadReentrant
        returns (uint256)
    {
        uint256 startTime_ = offerIdInfo[_offerId].startTime;
        uint256 offerPrice_ = offerIdInfo[_offerId].offerPrice;
        uint256 endPrice_ = dutchAuctionParams[_offerId].endPrice;
        uint256 dailyDiscount_ = dutchAuctionParams[_offerId].dailyDiscount;

        uint256 secondlyDiscount = dailyDiscount_ / 1 days;
        uint256 Discount = (block.timestamp - startTime_) * secondlyDiscount;
        uint256 price = offerPrice_ - Discount;
        if (price < endPrice_) {
            price = endPrice_;
        }
        return price;
    }


    function isOfferIdClosed(uint256 _offerId) 
        public 
        view 
        nonReadReentrant 
        returns (bool) {
        return offerClosed.get(_offerId);
    }

    function isBidIdClosed(uint256 _bidId) 
        public 
        view
        nonReadReentrant 
        returns (bool) {
        return bidClosed.get(_bidId);
    }

}

