pragma solidity ^0.8.0;

contract RandomNumberGenerator {
    function getRandomNumbers() public view returns (uint8[5] memory) {
        // 生成5个随机数值
        uint256[5] memory randomValues;
        for (uint8 i = 0; i < 5; i++) {
            randomValues[i] = uint256(keccak256(abi.encodePacked(block.timestamp, i)));
        }

        // 使用Fisher-Yates shuffle算法生成5个不同的随机索引值
        uint8[16] memory indices;
        for (uint8 i = 0; i < 16; i++) {
            indices[i] = i + 1;
        }
        for (uint8 i = 15; i > 10; i--) {
            uint8 j = uint8(randomValues[i - 11] % (i + 1));
            uint8 temp = indices[i];
            indices[i] = indices[j];
            indices[j] = temp;
        }

        // 从1-16中选择5个不同的数字
        uint8[5] memory numbers;
        for (uint8 i = 0; i < 5; i++) {
            numbers[i] = indices[i + 11];
        }

        return numbers;
    }
}