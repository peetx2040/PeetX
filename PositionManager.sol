// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Imports.sol";
import "./UniswapUtil.sol";

abstract contract PositionManager {
    using SafeERC20 for IERC20;

    address internal constant USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955;
    address internal constant VAULT_NFT_CONTRACT = 0x7b8A01B39D58278b5DE7e48c8449c9f4F5170613;
    uint256 internal constant VAULT_NFT_ID = 2796361;
    uint256 internal constant USDT_TO_LIQUIDITY_RATE = 9489590962000484160075646633;

    function _addLiquidityToNFT(address sender, uint256 amount) internal {
        IERC20(USDT_ADDRESS).safeTransferFrom(sender, address(this), amount);
        
        IERC20(USDT_ADDRESS).safeApprove(VAULT_NFT_CONTRACT, 0);
        IERC20(USDT_ADDRESS).safeApprove(VAULT_NFT_CONTRACT, amount);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: VAULT_NFT_ID,
            amount0Desired: amount,
            amount1Desired: 0,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 300
        });

        INonfungiblePositionManager(VAULT_NFT_CONTRACT).increaseLiquidity(params);
    }

    function _withdrawFromNFT(address recipient, uint256 usdtAmount) internal {
        if (usdtAmount == 0 || recipient == address(0)) return;

        uint128 liquidityToDecrease = uint128((usdtAmount * USDT_TO_LIQUIDITY_RATE) / 1 ether);

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
}
