 address public constant _FEE_RECEIVER ;
    uint256 constant _MAX_PRICE = type(uint128).max;
    uint256 constant _MAX_TIME= type(uint40).max;
    uint256 constant _MAX_TOKEN_ID= type(uint96).max;
    bytes4 constant _ERC165ID = 0x01ffc9a7;
    bytes4 constant _ERC721ID = 0x80ac58cd;


    /// @notice when the user attempts to mint after the dutch auction finishes
    error DutchAuctionOver();
    /// @notice when the admin attempts to withdraw funds before the dutch auction grace period has ended
    error DutchAuctionNotOver();
    /// @notice when `sender` does not pass the proper ether amount to `recipient`
    error FailedToSendEther(address sender, address recipient);
    /// @notice Raised when the mint has not reached the required timestamp

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

    struct  BidTicket {
        address buyer;
        uint40 bidTime;
        uint128 bidPrice;
        uint128 offerId;
    }


    uint256 public offerId;
    uint256 public bidId;
    uint256 public feeBasePoint = 50;
    mapping(uint256 => OfferTicket) public offerTicket; // mapping of offerId to offerTicket
    mapping(uint256 => DutchAuctionParams) public dutchAuctionParams; // mapping of offerId to dutchAuctionParams
    mapping(uint256 => BidTicket ) public bidIdInfo;

    /// @notice The instantiation of dutch auction parameters
    DutchAuctionParams public dutchParams;
    /// @notice The instantiation of the dutch auction finalization struct
    StandardAuctionParams public standardParams;
    