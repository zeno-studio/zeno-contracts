// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface INANFT {
        function ownerOf(uint256 tokenId) external view returns (address owner);
        function mint(address to, uint256 collateral, uint256 loanAmount,uint256 time) external  returns(uint256 tokenId);
        function burn(uint256 tokenId) external returns (bool) ;  
        function note(uint256 tokenId) external view returns (uint256 collateral, uint256 loanAmount, uint256 issuanceTime);
}