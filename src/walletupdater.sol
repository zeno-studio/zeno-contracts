// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract WalletManifestPointer {
    address public immutable OWNER;
    string public manifestArweaveTx;   // 永远只存这一行：Arweave 的 manifest.json 地址
    uint256 public updatedAt;

    constructor() { OWNER = msg.sender; }

    function update(string calldata newTxId) external {
        require(msg.sender == OWNER);
        manifestArweaveTx = newTxId;
        updatedAt = block.timestamp;
    }

    // Helios 每次打开只读这一个 view 函数
    function getManifest() external view returns (string memory, uint256) {
        return (manifestArweaveTx, updatedAt);
    }
}
