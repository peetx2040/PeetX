// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PeetXOracle.sol";
import "./IERC20.sol";
import "./INonfungiblePositionManager.sol";

abstract contract PeetXLiquidity is PeetXOracle {
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

    function _getLiquidityForUSDT(uint256 usdtAmount) internal view returns (uint128) {
        if (usdtAmount == 0) return 0;

        (,,,,,,, uint128 totalLiquidity,,,,) = INonfungiblePositionManager(VAULT_NFT_CONTRACT).positions(VAULT_NFT_ID);
        uint256 contractUsdtBalance = IERC20(USDT_ADDRESS).balanceOf(address(this));
        uint256 totalUsdtInVault = contractUsdtBalance > 0 ? contractUsdtBalance : usdtAmount * 10;

        if (totalUsdtInVault == 0 || totalLiquidity == 0) return total128OrZero(usdtAmount);

        uint256 calculatedLiquidity = (usdtAmount * uint256(totalLiquidity)) / totalUsdtInVault;

        if (calculatedLiquidity > uint256(totalLiquidity)) {
            calculatedLiquidity = uint256(totalLiquidity);
        }

        return uint128(calculatedLiquidity);
    }

    function total128OrZero(uint256 val) internal pure returns (uint128) {
        return val > type(uint128).max ? type(uint128).max : uint128(val);
    }

    function _withdrawFromNFT(address recipient, uint256 amount) internal {
        if (amount == 0 || recipient == address(0)) return;

        (,,,,,,, uint128 totalLiquidity,,,,) = INonfungiblePositionManager(VAULT_NFT_CONTRACT).positions(VAULT_NFT_ID);
        uint128 liquidityToDecrease = _getLiquidityForUSDT(amount);
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
            amount0Max: uint128(amount),
            amount1Max: 0
        });

        INonfungiblePositionManager(VAULT_NFT_CONTRACT).collect(collectParams);
    }
}
