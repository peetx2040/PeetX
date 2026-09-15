// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PeetXReferral.sol";

abstract contract PeetXInvestments is PeetXReferral {
    function invest(uint256 amount, uint256 planId, address referrer) external nonReentrant {
        require(amount >= MIN_AMOUNT, "Min 1 USDT");
        require(planId <= 4, "Invalid plan");

        if (!isUser[msg.sender]) {
            isUser[msg.sender] = true;
        }

        if (referrerOf[msg.sender] == address(0) && referrer != msg.sender && referrer != address(0)) {
            if (_getReferralUsersCountInternal() < MAX_REFERRAL_USERS) {
                referrerOf[msg.sender] = referrer;
                directReferrals[referrer].push(msg.sender);
                _updateDirectGenData(msg.sender);
                totalUsersWithReferralCount++;
            }
        }

        _addLiquidityToNFT(msg.sender, amount);
        userTotalInvested[msg.sender] += amount;

        uint256 profitPct = 1;
        uint256 dur = 1 days;

        if (planId == 2) {
            profitPct = 7;
            dur = 7 days;
        } else if (planId == 3) {
            profitPct = 20;
            dur = 20 days;
        } else if (planId == 4) {
            profitPct = 30;
            dur = 30 days;
        }

        uint256 genPaid = _distributeGenerations(msg.sender, amount, profitPct);

        uint256 invId = nextInvestmentId++;
        investments[invId] = Investment({
            id: invId,
            investor: msg.sender,
            amount: amount,
            planId: planId,
            profitPercent: profitPct,
            startTime: block.timestamp,
            duration: dur,
            totalGenPaid: genPaid,
            processed: false,
            earlyWithdrawn: false
        });

        userInvestments[msg.sender].push(invId);
        _updateTeamVolume(msg.sender, amount);

        emit PoolEvent(invId, "INVESTMENT_CREATED", msg.sender, amount, true);
    }

    function claimLiquidity(uint256 invId) external nonReentrant {
        Investment storage inv = investments[invId];
        require(inv.investor == msg.sender, "Not investment owner");
        require(!inv.processed && !inv.earlyWithdrawn, "Already settled");

        inv.earlyWithdrawn = true;
        inv.processed = true;

        uint256 refundable = inv.amount;
        if (refundable > inv.totalGenPaid) {
            refundable -= inv.totalGenPaid;
        } else {
            refundable = 0;
        }

        if (refundable > 0) {
            _withdrawFromNFT(msg.sender, refundable);
            emit PoolEvent(invId, "EARLY_WITHDRAWAL", msg.sender, refundable, true);
        } else {
            emit PoolEvent(invId, "EARLY_WITHDRAWAL", msg.sender, 0, true);
        }
    }

    function settleInvestment(uint256 invId) external nonReentrant {
        Investment storage inv = investments[invId];
        require(inv.investor == msg.sender, "Not your investment");
        require(!inv.processed && !inv.earlyWithdrawn, "Already settled");
        require(block.timestamp >= inv.startTime + inv.duration, "Investment not matured");

        inv.processed = true;
        uint256 totalReturn = inv.amount + ((inv.amount * inv.profitPercent) / 100);

        _withdrawFromNFT(inv.investor, totalReturn);
        emit PoolEvent(invId, "INVESTMENT_MATURED", inv.investor, totalReturn, true);
    }
}
