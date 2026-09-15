// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PeetXViews.sol";
import "./AggregatorV3Interface.sol";

abstract contract PeetXOracle is PeetXViews {
    function _getLatestPrice() internal view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(CHAINLINK_FEED).latestRoundData();
        require(price > 0, "Invalid price feed");
        return uint256(price);
    }
}
