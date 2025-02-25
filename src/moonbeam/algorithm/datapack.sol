// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract DataPack {
    
       struct OfferTicket {
        address seller;
        uint40 startTime;
        uint40 endTime;
        uint8 offerStatus; // 0:open, 1:caceled,2:sold
        uint8 offerMethod; // (0:standard, 1:dutch) 
    }

    OfferTicket public ticket;
    uint256 packedData ;

    function pack(address  _address, uint256 _starttime, uint256 _endtime, uint256 _status, uint256 _method) public  returns (uint256 ) {
        // 将数据打包成一个uint256
        packedData = (uint256(uint160(_address)) << 96) | (_starttime << 56) | (_endtime << 16) | (_status << 8) | _method;

        return packedData;

    }

    function unpack() public view returns (address _address, uint40 _starttime, uint40 _endtime, uint8 _status, uint8 _method) {
        // 将数据解包
        _address = address(uint160(packedData >> 96));
        _starttime = uint40((packedData >> 56) & 0xFFFFFFFFFF);
        _endtime = uint40((packedData >> 16) & 0xFFFFFFFFFF);
        _status = uint8((packedData >> 8) & 0xFF);
        _method = uint8(packedData & 0xFF);

        return ( _address, _starttime, _endtime, _status, _method);
    }

    function setStuct (address _address, uint256  _starttime, uint256  _endtime, uint256  _status, uint256   _method) public   {
        ticket.seller = _address;
        ticket.startTime = uint40(_starttime);
        ticket.endTime = uint40(_endtime);
        ticket.offerStatus = uint8(_status);
        ticket.offerMethod= uint8(_method);

    }

    function readStuct () public view returns (address _address, uint40 _starttime, uint40 _endtime, uint8 _status, uint8 _method) {
        OfferTicket memory _ticket;
         _ticket = ticket;
         return (_ticket.seller, _ticket.startTime, _ticket.endTime, _ticket.offerStatus, _ticket.offerMethod);
    }

    function updatePackedAddress(uint256 packedData, address _address) public pure returns (uint256) {
    // 清除原地址
    packedData &= ~(uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) << 96);
    // 更新地址
    packedData |= uint160(_address) << 96;;
    return packedData;
    }

    function updatePackedStartTime(uint256 packedData, uint40 _starttime) public pure returns (uint256) {
    packedData &= ~(uint256(0xFFFFFFFFFF) << 56);
    packedData |= uint256(_starttime) << 56;
    return packedData;
}

function updatePackedEndtime(uint256 packedData, uint40 _endtime) public pure returns (uint256) {
    packedData &= ~(uint256(0xFFFFFFFFFF) << 16);
    packedData |= uint256(_endtime) << 16;
    return packedData;
}

function updatePackedStatus(uint256 packedData, uint8 _status) public pure returns (uint256) {
    packedData &= ~(uint256(0xFF) << 8);
    packedData |= uint256(newUint8_1) << 8;
    return packedData;
}

}

