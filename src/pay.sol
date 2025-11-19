// Pay7702.sol
contract Pay7702 {
    event Payment(
        address indexed payer,
        address indexed merchant,     // 注册的商户地址
        uint256 amount,
        uint256 indexed orderId,       // merchantId (u128) << 128 | orderSeq (u128)
        bytes data                     // 商户自定义
    );

    // 商户注册表：merchantAddr => info
    mapping(address => MerchantInfo) public merchants;
    struct MerchantInfo {
        string name;       // "京东", "淘宝", "OnlyFans"
        string url;        // 回调域名（仅供展示）
        bool active;
    }

    // 任何人都可以注册（无许可）
    function registerMerchant(string calldata name, string calldata url) external {
        merchants[msg.sender] = MerchantInfo(name, url, true);
    }

    // 核心支付函数（7702 交易会调用这个）
    function pay(uint256 orderId, bytes calldata extra) external payable {
        address merchant = tx.origin; // 7702 保证是真实 EOA
        require(merchants[merchant].active, "not registered");

        emit Payment(msg.sender, merchant, msg.value, orderId, extra);
    }
}
