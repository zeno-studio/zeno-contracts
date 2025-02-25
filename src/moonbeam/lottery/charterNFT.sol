// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// bitmap 让tokenid 可选
// lv 5：1   10000glmr
// lv 4：2-9 5000 glmr
// lv 3：10-99 2000 glmr
// lv 2：100-999    500 glmr
// lv 1：1000-9999   100 glmr
// 分账制 zom 50% team 50%

import {ERC721} from "@openzeppelin-contracts-5.1.0/token/ERC721/ERC721.sol";
import {ERC721} from "solady-0.0.265/tokens/ERC721.sol";

contract Chart is ERC721 {

   constructor() ERC721("ZENO LOTTERY CHARTER of MOONBEAM", "ZLC") {}


}


