// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "solady-0.0.265/tokens/ERC721.sol";
import {Ownable} from "solady-0.0.265/auth/Ownable.sol";
import {Base64} from"solady-0.0.265/utils/Base64.sol";

contract NoteNFT is ERC721, Ownable{
    constructor() {

    }

    address public operator;
    uint256 public currentTokenId;

    struct loanInfo {
        uint96 collateral;
        uint120 loanAmount;
        uint40 issuanceTime;   
    }
    mapping(uint256 => loanInfo) public note;

    modifier onlyOperator() {
        require(msg.sender == operator, "Only operator can call this function");
        _;
    }

    function name() public pure override returns (string memory) {
        return "novation Agreement of ZOM";
    }

    function symbol() public pure override returns (string memory) {
        return "ZNA";
    }


    function setOperator(address _operator) public onlyOwner {
        operator = _operator;
    }

    function mint(address to, uint256  collateral, uint256  loanAmount,uint256 time) public onlyOperator  returns(uint256 tokenId) {
        require(currentTokenId < 10000, "Max token ID reached");
        ++currentTokenId;
        tokenId = currentTokenId;
        note[tokenId].collateral = collateral;
        note[tokenId].loanAmount = loanAmount;
        note[tokenId].issuanceTime = time;
        _mint(to, tokenId);
        emit NftMinted(to,tokenId);
        return tokenId;

    }
    function burn(uint256 tokenId) public onlyOperator returns (bool) {
        _burn(tokenId);
        return true;
    }

    function _afterTokenTransfer(address from, address to, uint256 id) internal virtual {
        uint256 amount = note[id].collateral;
        bytes data = abi.encodeWithSignature("transferPersonalMortgage(address,address,uint256)", from, to, amount);
        (bool success,) = operator.call(data); 
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      SVG NFT module                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function tokenURI(uint256 tokenId)
    public
    view
    override
    returns (string memory)
{
    require(ownerOf(tokenId) != address(0), "ERC721Metadata: URI query for nonexistent token");
    require(tokenId > 0 && tokenId < type(uint256).max, ("ERC721Metadata: URI query for nonexistent token" ), "ERC721Metadata: URI query for nonexistent token");
    return
        render(tokenId);
}



    function render(uint256 memory tokenId) public returns (string memory) {
    
    string memory image = string.concat(
    "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 290 500'>",
    "<style>.tokens { font: bold 30px sans-serif; }",
    ".fee { font: normal 26px sans-serif; }",
    ".tick { font: normal 18px sans-serif; }</style>",
    renderBackground(note[tokenId].collateral),
    renderTop(tokenId),
    renderBottom(note[tokenId].collateral,note[tokenId].loanAmount,note[tokenId].issuanceTime),
    "</svg>"
    );

    string memory description = renderDescription(tokenId);

    string memory json = string.concat(
        '{"name":"Uniswap V3 Position",',
        '"description":"',
        description,
        '",',
        '"image":"data:image/svg+xml;base64,',
        encode(bytes(image)),
        '"}'
    );
    return
    string.concat(
        "data:application/json;base64,",
        encode(bytes(json))
    );

    }

    function renderBackground(
    uint256 memory collateral
    ) internal pure returns (string memory background) {
    bytes32 key = keccak256(abi.encodePacked(owner, lowerTick, upperTick));
    uint256 hue = uint256(key) % 360;

    background = string.concat(
        '<rect width="300" height="480" fill="hsl(',
        Strings.toString(hue),
        ',40%,40%)"/>',
        '<rect x="30" y="30" width="240" height="420" rx="15" ry="15" fill="hsl(',
        Strings.toString(hue),
        ',100%,50%)" stroke="#000"/>'
    );
}

    function renderTop(
    uint256 memory tokenId
    ) internal pure returns (string memory top) {
    top = string.concat(
        '<rect x="30" y="87" width="240" height="42"/>',
        '<text x="39" y="120" class="tokens" fill="#fff">',
        symbol0,
        "/",
        symbol1,
        "</text>"
        '<rect x="30" y="132" width="240" height="30"/>',
        '<text x="39" y="120" dy="36" class="fee" fill="#fff">',
        feeToText(fee),
        "</text>"
    );
}

function renderBottom(
    uint256 memory collateral,
    uint256 memory loanAmount,
    uint256 memory issuanceTime
    )
    internal
    pure
    returns (string memory bottom)
{
    bottom = string.concat(
        '<rect x="30" y="342" width="240" height="24"/>',
        '<text x="39" y="360" class="tick" fill="#fff">Lower tick: ',
        collateral+issuanceTime,
        "</text>",
        '<rect x="30" y="372" width="240" height="24"/>',
        '<text x="39" y="360" dy="30" class="tick" fill="#fff">Upper tick: ',
        loanAmount,
        "</text>"
    );
}

function renderDescription(
    uint256 memory tokenId
) internal pure returns (string memory description) {
    description = string.concat(
        "Mortgage Amount: ",
        note[tokenId].collateral,
        " Loan Amount: ",
        note[tokenId].loanAmount,
        " Issuance Time: ",
        note[tokenId].issuanceTime
    );
}

function formatToSixDecimals(uint256 amount) internal pure returns (string memory) {
    uint256 wholePart = amount / 10**18;
    uint256 fractionalPart = (amount % 10**18) * 10**6 / 10**18; // 取小数部分并扩大到六位
    return string.concat(
        Strings.toString(wholePart),
        ".",
        Strings.toString(fractionalPart)
    );
}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     dateTimelib       
    /*   copy from solady                                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

function epochDayToDate(uint256 epochDay)
        internal
        pure
        returns (uint256 year, uint256 month, uint256 day)
    {
        /// @solidity memory-safe-assembly
        assembly {
            epochDay := add(epochDay, 719468)
            let doe := mod(epochDay, 146097)
            let yoe :=
                div(sub(sub(add(doe, div(doe, 36524)), div(doe, 1460)), eq(doe, 146096)), 365)
            let doy := sub(doe, sub(add(mul(365, yoe), shr(2, yoe)), div(yoe, 100)))
            let mp := div(add(mul(5, doy), 2), 153)
            day := add(sub(doy, shr(11, add(mul(mp, 62719), 769))), 1)
            month := byte(mp, shl(160, 0x030405060708090a0b0c0102))
            year := add(add(yoe, mul(div(epochDay, 146097), 400)), lt(month, 3))
        }
    }

    function timestampToDate(uint256 timestamp)
        internal
        pure
        returns (uint256 year, uint256 month, uint256 day)
    {
        (year, month, day) = epochDayToDate(timestamp / 86400);
    }


    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     libString      
    /*   copy from solady                                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function toString(uint256 value) internal pure returns (string memory result) {
        /// @solidity memory-safe-assembly
        assembly {
            // The maximum value of a uint256 contains 78 digits (1 byte per digit), but
            // we allocate 0xa0 bytes to keep the free memory pointer 32-byte word aligned.
            // We will need 1 word for the trailing zeros padding, 1 word for the length,
            // and 3 words for a maximum of 78 digits.
            result := add(mload(0x40), 0x80)
            mstore(0x40, add(result, 0x20)) // Allocate memory.
            mstore(result, 0) // Zeroize the slot after the string.

            let end := result // Cache the end of the memory to calculate the length later.
            let w := not(0) // Tsk.
            // We write the string from rightmost digit to leftmost digit.
            // The following is essentially a do-while loop that also handles the zero case.
            for { let temp := value } 1 {} {
                result := add(result, w) // `sub(result, 1)`.
                // Store the character to the pointer.
                // The ASCII index of the '0' character is 48.
                mstore8(result, add(48, mod(temp, 10)))
                temp := div(temp, 10) // Keep dividing `temp` until zero.
                if iszero(temp) { break }
            }
            let n := sub(end, result)
            result := sub(result, 0x20) // Move the pointer 32 bytes back to make room for the length.
            mstore(result, n) // Store the length.
        }
    }


}