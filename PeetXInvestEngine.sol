// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract PeetXInvestEngine {
    uint256 internal totalUsersWithReferralCount;
    uint256[5] internal GEN_RATES = [25, 20, 15, 10, 5];
    uint256[5] internal GEN_MIN_INVEST = [100 * 10**18, 200 * 10**18, 300 * 10**18, 400 * 10**18, 500 * 10**18];

    struct Investment {
        uint256 id;
        address investor;
        uint256 amount;
        uint256 planId;
        uint256 profitPercent;
        uint256 startTime;
        uint256 duration;
        uint256 totalGenPaid;
        bool processed;
        bool earlyWithdrawn;
    }

    struct UserGenData {
        uint256[5] counts;
        uint256[5] volumes;
        uint256 totalEarnings;
        address referrer;
        uint256 directReferralCount;
        uint256 teamVolume;
        uint256 totalInvested;
    }

    uint256 internal nextInvestmentId;
    uint256 internal investmentCursor;

    mapping(uint256 => Investment) internal investments;
    mapping(address => address) internal referrerOf;
    mapping(address => address[]) internal directReferrals;
    mapping(address => uint256) internal userTotalGenEarnings;
    mapping(address => uint256) internal userTeamVolume;
    mapping(address => uint256[5]) internal userGenCount;
    mapping(address => uint256[5]) internal userGenVolume;
    mapping(address => uint256[]) internal userInvestments;
    mapping(address => bool) internal isUser;
    mapping(address => uint256) internal userTotalInvested;

    function _getReferralUsersCountInternal() internal view returns (uint256) {
        return totalUsersWithReferralCount;
    }

    function _updateDirectGenData(address user) internal {
        address curr = referrerOf[user];
        if (curr != address(0)) userGenCount[curr][0]++;
        if (curr != address(0) && referrerOf[curr] != address(0)) userGenCount[referrerOf[curr]][1]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0)) userGenCount[referrerOf[referrerOf[curr]]][2]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0) && referrerOf[referrerOf[referrerOf[curr]]] != address(0)) userGenCount[referrerOf[referrerOf[referrerOf[curr]]]][3]++;
        if (curr != address(0) && referrerOf[curr] != address(0) && referrerOf[referrerOf[curr]] != address(0) && referrerOf[referrerOf[referrerOf[curr]]] != address(0) && referrerOf[referrerOf[referrerOf[referrerOf[curr]]]] != address(0)) userGenCount[referrerOf[referrerOf[referrerOf[referrerOf[curr]]]][4]++;
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
}
