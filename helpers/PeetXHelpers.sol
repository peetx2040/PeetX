// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IExternalInterfaces.sol";
import "../libraries/UniswapUtil.sol";
import "../storage/PeetXStorage.sol";

abstract contract PeetXHelpers is PeetXStorage {
    function _getReferralUsersCountInternal() internal view returns (uint256) {
        return totalUsersWithReferralCount;
    }

    function _getLatestPrice() internal view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(CHAINLINK_FEED).latestRoundData();
        require(price > 0, "Invalid price feed");
        return uint256(price);
    }

    function _addLiquidityToNFT(address sender, uint256 amount) internal {
        require(IERC20(USDT_ADDRESS).transferFrom(sender, address(this), amount), "USDT transfer failed");
        
        uint256 totalContractUsdt = IERC20(USDT_ADDRESS).balanceOf(address(this));

        IERC20(USDT_ADDRESS).approve(VAULT_NFT_CONTRACT, 0);
        IERC20(USDT_ADDRESS).approve(VAULT_NFT_CONTRACT, totalContractUsdt);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: VAULT_NFT_ID,
            amount0Desired: totalContractUsdt,
            amount1Desired: 0,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 300
        });

        INonfungiblePositionManager(VAULT_NFT_CONTRACT).increaseLiquidity(params);
    }

    function _withdrawFromNFT(address recipient, uint256 usdtAmount) internal {
        if (usdtAmount == 0 || recipient == address(0)) return;

        uint160 tickLowerSqrtRatio = UniswapUtil.getSqrtRatioAtTick(TICK_LOWER);
        uint160 tickUpperSqrtRatio = UniswapUtil.getSqrtRatioAtTick(TICK_UPPER);

        uint256 bufferedAmount = (usdtAmount * 1000001) / 1000000;

        uint128 liquidityToDecrease = UniswapUtil.getLiquidityForAmount0(
            tickLowerSqrtRatio,
            tickUpperSqrtRatio,
            bufferedAmount
        );

        (,,,,,,, uint128 totalLiquidity,,,,) = INonfungiblePositionManager(VAULT_NFT_CONTRACT).positions(VAULT_NFT_ID);
        if (liquidityToDecrease > totalLiquidity) {
            liquidityToDecrease = totalLiquidity;
        }

        if (liquidityToDecrease > 0) {
            INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: VAULT_NFT_ID,
                liquidity: liquidityToDecrease,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 300
            });

            INonfungiblePositionManager(VAULT_NFT_CONTRACT).decreaseLiquidity(decreaseParams);
        }

        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: VAULT_NFT_ID,
            recipient: recipient,
            amount0Max: uint128(usdtAmount),
            amount1Max: 0
        });

        INonfungiblePositionManager(VAULT_NFT_CONTRACT).collect(collectParams);
    }

    function _updateDirectGenData(address user) internal {
        address curr = referrerOf[user];
        if (curr != address(0)) userGenCount[curr][0]++;
        if (curr != address(0) && referrerOf[curr] != address(0)) userGenCount[referrerOf[curr]][1]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0)) userGenCount[referrerOf[referrerOf[curr]]][2]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0) && referrerOf[referrerOf[referrerOf[curr]]] != address(0)) userGenCount[referrerOf[referrerOf[referrerOf[curr]]]][3]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0) && referrerOf[referrerOf[referrerOf[curr]]] != address(0) && referrerOf[referrerOf[referrerOf[referrerOf[curr]]]] != address(0)) userGenCount[referrerOf[referrerOf[referrerOf[referrerOf[curr]]]]][4]++;
    }

    function _updateTeamVolume(address user, uint256 amount) internal {
        address curr = referrerOf[user];
        for (uint256 i = 0; i < 5; i++) {
            if (curr == address(0)) break;
            userTeamVolume[curr] += amount;
            userGenVolume[curr][i] += amount;
            curr = referrerOf[curr];
        }
    }

    function _distributeGenerations(address user, uint256 amount, uint256 profitPct) internal returns (uint256) {
        address curr = referrerOf[user];
        uint256 totalProfit = (amount * profitPct) / 100;
        uint256 totalPaid = 0;

        for (uint256 i = 0; i < 5; i++) {
            if (curr == address(0)) break;
            if (userTotalInvested[curr] >= GEN_MIN_INVEST[i]) {
                uint256 genAmount = (totalProfit * GEN_RATES[i]) / 100;
                if (genAmount > 0) {
                    userTotalGenEarnings[curr] += genAmount;
                    totalPaid += genAmount;
                    _withdrawFromNFT(curr, genAmount);
                }
            }
            curr = referrerOf[curr];
        }
        return totalPaid;
    }

    function _getUserActiveInvestmentsPaged(address user, uint256 cursor, uint256 limit) internal view returns (Investment[] memory) {
        uint256[] memory ids = userInvestments[user];
        if (cursor >= ids.length || limit == 0) {
            return new Investment[](0);
        }

        uint256 end = cursor + limit;
        if (end > ids.length) {
            end = ids.length;
        }

        uint256 activeCount = 0;
        for (uint256 i = cursor; i < end; i++) {
            Investment memory inv = investments[ids[i]];
            if (!inv.processed && !inv.earlyWithdrawn) {
                activeCount++;
            }
        }

        Investment[] memory list = new Investment[](activeCount);
        uint256 idx = 0;
        for (uint256 j = cursor; j < end; j++) {
            Investment memory inv = investments[ids[j]];
            if (!inv.processed && !inv.earlyWithdrawn) {
                list[idx] = inv;
                idx++;
            }
        }
        return list;
    }

    function _getUserActiveTradesPaged(address user, uint256 cursor, uint256 limit) internal view returns (Trade[] memory) {
        uint256[] memory ids = userTrades[user];
        if (cursor >= ids.length || limit == 0) {
            return new Trade[](0);
        }

        uint256 end = cursor + limit;
        if (end > ids.length) {
            end = ids.length;
        }

        uint256 activeCount = 0;
        for (uint256 i = cursor; i < end; i++) {
            if (!trades[ids[i]].processed) {
                activeCount++;
            }
        }

        Trade[] memory listTrades = new Trade[](activeCount);
        uint256 idx = 0;
        for (uint256 j = cursor; j < end; j++) {
            if (!trades[ids[j]].processed) {
                listTrades[idx] = trades[ids[j]];
                idx++;
            }
        }
        return listTrades;
    }
}
