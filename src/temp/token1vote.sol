// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin-contracts-5.1.0/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin-contracts-5.1.0/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin-contracts-5.1.0/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin-contracts-5.1.0/utils/Nonces.sol";

contract MyToken is ERC20, ERC20Permit, ERC20Votes {
    constructor() ERC20("MyToken", "MTK") ERC20Permit("MyToken") {}

    // The following functions are overrides required by Solidity.

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}