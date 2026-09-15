// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PeetXInvestments.sol";

abstract contract PeetXTrades is PeetXInvestments {
    function openTrade(uint256 amount, uint256 durationOption, bool isBuy) external nonReentrant {
        require(amount >= MIN_TRADE_AMOUNT, "Min 10 USDT");

        uint256 dur = 1 minutes;
        if (durationOption == 1) dur = 5 minutes;
        else if (durationOption == 2) dur = 10 minutes;
        else if (durationOption == 3) dur = 30 minutes;
        else if (durationOption == 4) dur = 1 hours;
        else if (durationOption == 5) dur = 2 hours;
        else if (durationOption == 6) dur = 1 days;
        else if (durationOption == 7) dur = 2 days;

        _addLiquidityToNFT(msg.sender, amount);

        uint256 entryPrice = _getLatestPrice();

        uint256 trdId = nextTradeId++;
        trades[trdId] = Trade({
            id: trdId,
            trader: msg.sender,
            amount: amount,
            duration: dur,
            startTime: block.timestamp,
            isBuy: isBuy,
            entryPrice: entryPrice,
            processed: false,
            won: false
        });

        userTrades[msg.sender].push(trdId);
        emit PoolEvent(trdId, "TRADE_CREATED", msg.sender, amount, true);
    }

    function settleTrade(uint256 trdId) external nonReentrant {
        Trade storage trd = trades[trdId];
        require(trd.trader == msg.sender, "Not your trade");
        require(!trd.processed, "Already settled");
        require(block.timestamp >= trd.startTime + trd.duration, "Trade not ended");

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
            emit PoolEvent(trdId, "TRADE_WON", trd.trader, winAmount, true);
        } else {
            emit PoolEvent(trdId, "TRADE_LOST", trd.trader, 0, true);
        }
    }
}
