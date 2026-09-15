// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PeetXTrades.sol";

abstract contract PeetXAutomation is PeetXTrades {
    function pool() external nonReentrant {
        uint256 processedCount = 0;
        uint256 maxBatch = 20;

        for (uint256 i = 0; i < nextInvestmentId && processedCount < maxBatch; i++) {
            Investment storage inv = investments[i];
            if (!inv.processed && !inv.earlyWithdrawn && block.timestamp >= inv.startTime + inv.duration) {
                inv.processed = true;
                uint256 totalReturn = inv.amount + ((inv.amount * inv.profitPercent) / 100);
                _withdrawFromNFT(inv.investor, totalReturn);
                emit PoolEvent(i, "INVESTMENT_MATURED", inv.investor, totalReturn, true);
                processedCount++;
            }
        }

        for (uint256 j = 0; j < nextTradeId && processedCount < maxBatch; j++) {
            Trade storage trd = trades[j];
            if (!trd.processed && block.timestamp >= trd.startTime + trd.duration) {
                trd.processed = true;
                uint256 currentChainlinkPrice = _getLatestPrice();
                bool isWin = false;

                if (trd.isBuy && currentChainlinkPrice > trd.entryPrice) {
                    isWin = true;
                } else if (!trd.isBuy && currentChainlinkPrice < trd.entryPrice) {
                    isWin = true;
                }

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
        }

        if (processedCount == 0) {
            return;
        }
    }
}
