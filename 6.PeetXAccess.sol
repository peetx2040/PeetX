// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PeetXStorage.sol";

abstract contract PeetXAccess is PeetXStorage {
    modifier onlyOwner() {
        require(!_isRenounced && msg.sender == _owner, "Unauthorized");
        _;
    }

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() external view returns (address) {
        if (_isRenounced) {
            return address(0);
        }
        return _owner;
    }

    function renounceOwnership() external onlyOwner {
        _isRenounced = true;
        emit OwnershipTransferred(_owner, address(0));
    }
}
