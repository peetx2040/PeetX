// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PeetXLiquidity.sol";

abstract contract PeetXReferral is PeetXLiquidity {
    function _getReferralUsersCountInternal() internal view returns (uint256) {
        return totalUsersWithReferralCount;
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
}
