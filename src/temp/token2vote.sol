// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20Votes} from "solady-0.0.265/tokens/ERC20Votes.sol";

contract Token2Vote is ERC20Votes {
    constructor() {}
        function name() public pure override returns (string memory) {
        return "Zeno vote ";
    }

    function symbol() public pure override returns (string memory) {
        return "ZenV";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
    
    // max=1_000_000_000*10**18
    function maxSupply() public pure  returns (uint256) {
        return 1000000000000000000000000000;
    }
}