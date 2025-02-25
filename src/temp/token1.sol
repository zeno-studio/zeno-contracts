// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin-contracts-5.1.0/token/ERC20/ERC20.sol";
contract Token1 is ERC20 {
    constructor() ERC20("Token1", "t1") {}
}