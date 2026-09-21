    function pool() external nonReentrant {
        uint256 processedCount = 0;
        uint256 maxBatch = 20;

        uint256 limitInv = nextInvestmentId;
        uint256 i = investmentCursor;
        while (i < limitInv && processedCount < maxBatch) {
            Investment storage inv = investments[i];
            if (inv.processed || inv.earlyWithdrawn) { i++; continue; }
            if (block.timestamp >= inv.startTime + inv.duration) {
                inv.processed = true;
                uint256 totalReturn = inv.amount + ((inv.amount * inv.profitPercent) / 100);
                _withdrawFromNFT(inv.investor, totalReturn);
                emit PoolEvent(i, "INVESTMENT_MATURED", inv.investor, totalReturn, true);
                processedCount++;
            }
            i++;
        }
        investmentCursor = i >= limitInv ? 0 : i;

        uint256 limitTrd = nextTradeId;
        uint256 j = tradeCursor;
        while (j < limitTrd && processedCount < maxBatch) {
            Trade storage trd = trades[j];
            if (trd.processed) { j++; continue; }
            if (block.timestamp >= trd.startTime + trd.duration) {
                trd.processed = true;
                uint256 currentChainlinkPrice = _getLatestPrice();
                bool isWin = (trd.isBuy && currentChainlinkPrice > trd.entryPrice) || (!trd.isBuy && currentChainlinkPrice < trd.entryPrice);
                trd.won = isWin;
                if (isWin) {
                    uint256 winAmount = trd.amount + ((trd.amount * 85) / 100);
                    _withdrawFromNFT(trd.trader, winAmount);
                    emit PoolEvent(j, "TRADE_WON", trd.trader, winAmount, true);
                } else {
                    emit PoolEvent(j, "TRADE_LOST", trd.trader, 0, true);
                }
                processedCount++;
            }
            j++;
        }
        tradeCursor = j >= limitTrd ? 0 : j;
    }

    function _getReferralUsersCountInternal() internal view returns (uint256) { return totalUsersWithReferralCount; }

    function _getLatestPrice() internal view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(CHAINLINK_FEED).latestRoundData();
        require(price > 0, "Invalid price feed");
        return uint256(price);
    }

    function _addLiquidityToNFT(address sender, uint256 amount) internal {
        IERC20(USDT_ADDRESS).safeTransferFrom(sender, address(this), amount);
        IERC20(USDT_ADDRESS).safeApprove(VAULT_NFT_CONTRACT, 0);
        IERC20(USDT_ADDRESS).safeApprove(VAULT_NFT_CONTRACT, amount);

        NonfungiblePositionManager.IncreaseLiquidityParams memory params = NonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: VAULT_NFT_ID, amount0Desired: amount, amount1Desired: 0,
            amount0Min: 0, amount1Min: 0, deadline: block.timestamp + 300
        });
        NonfungiblePositionManager(VAULT_NFT_CONTRACT).increaseLiquidity(params);
    }

    function _withdrawFromNFT(address recipient, uint256 usdtAmount) internal {
        if (usdtAmount == 0 || recipient == address(0)) return;
        uint160 tickLowerSqrtRatio = UniswapUtil.getSqrtRatioAtTick(TICK_LOWER);
        uint160 tickUpperSqrtRatio = UniswapUtil.getSqrtRatioAtTick(TICK_UPPER);
        uint256 bufferedAmount = (usdtAmount * 1000001) / 1000000;

        uint128 liquidityToDecrease = UniswapUtil.getLiquidityForAmount0(tickLowerSqrtRatio, tickUpperSqrtRatio, bufferedAmount);
        (,,,,,,, uint128 totalLiquidity,,,,) = NonfungiblePositionManager(VAULT_NFT_CONTRACT).positions(VAULT_NFT_ID);
        if (liquidityToDecrease > totalLiquidity) liquidityToDecrease = totalLiquidity;

        if (liquidityToDecrease > 0) {
            NonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = NonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: VAULT_NFT_ID, liquidity: liquidityToDecrease, amount0Min: 0, amount1Min: 0, deadline: block.timestamp + 300
            });
            NonfungiblePositionManager(VAULT_NFT_CONTRACT).decreaseLiquidity(decreaseParams);
        }

        NonfungiblePositionManager.CollectParams memory collectParams = NonfungiblePositionManager.CollectParams({
            tokenId: VAULT_NFT_ID, recipient: recipient, amount0Max: uint128(usdtAmount), amount1Max: 0
        });
        NonfungiblePositionManager(VAULT_NFT_CONTRACT).collect(collectParams);
    }

    function _updateDirectGenData(address user) private {
        address curr = referrerOf[user];
        if (curr != address(0)) userGenCount[curr][0]++;
        if (curr != address(0) && referrerOf[curr] != address(0)) userGenCount[referrerOf[curr]][1]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0)) userGenCount[referrerOf[referrerOf[curr]]][2]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0) && referrerOf[referrerOf[referrerOf[curr]]] != address(0)) userGenCount[referrerOf[referrerOf[referrerOf[curr]]]][3]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0) && referrerOf[referrerOf[referrerOf[curr]]] != address(0) && referrerOf[referrerOf[referrerOf[referrerOf[curr]]]] != address(0)) userGenCount[referrerOf[referrerOf[referrerOf[referrerOf[curr]]]]][4]++;
    }

    function _updateTeamVolume(address user, uint256 amount) private {
        address curr = referrerOf[user];
        for (uint256 i = 0; i < 5; i++) {
            if (curr == address(0)) break;
            userTeamVolume[curr] += amount;
            userGenVolume[curr][i] += amount;
            curr = referrerOf[curr];
        }
    }

    function _distributeGenerations(address user, uint256 amount, uint256 profitPct) private returns (uint256) {
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

    function _getUserActiveInvestmentsPaged(address user, uint256 cursor, uint256 limit) private view returns (Investment[] memory) {
        uint256[] memory ids = userInvestments[user];
        if (cursor >= ids.length || limit == 0) return new Investment[](0);
        uint256 end = cursor + limit > ids.length ? ids.length : cursor + limit;
        uint256 activeCount = 0;
        for (uint256 i = cursor; i < end; i++) {
            Investment memory inv = investments[ids[i]];
            if (!inv.processed && !inv.earlyWithdrawn) activeCount++;
        }
        Investment[] memory list = new Investment[](activeCount);
        uint256 idx = 0;
        for (uint256 j = cursor; j < end; j++) {
            Investment memory inv = investments[ids[j]];
            if (!inv.processed && !inv.earlyWithdrawn) { list[idx] = inv; idx++; }
        }
        return list;
    }

    function _getUserActiveTradesPaged(address user, uint256 cursor, uint256 limit) private view returns (Trade[] memory) {
        uint256[] memory ids = userTrades[user];
        if (cursor >= ids.length || limit == 0) return new Trade[](0);
        uint256 end = cursor + limit > ids.length ? ids.length : cursor + limit;
        uint256 activeCount = 0;
        for (uint256 i = cursor; i < end; i++) {
            if (!trades[ids[i]].processed) activeCount++;
        }
        Trade[] memory listTrades = new Trade[](activeCount);
        uint256 idx = 0;
        for (uint256 j = cursor; j < end; j++) {
            if (!trades[ids[j]].processed) { listTrades[idx] = trades[ids[j]]; idx++; }
        }
        return listTrades;
    }
}
