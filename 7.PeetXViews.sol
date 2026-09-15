// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PeetXAccess.sol";

abstract contract PeetXViews is PeetXAccess {
    function USDT() external view returns (address) {
        return USDT_ADDRESS;
    }

    function NonfungiblePositionManager() external view returns (address) {
        return VAULT_NFT_CONTRACT;
    }

    function Chainlink() external view returns (bool) {
        uint256 limitInv = nextInvestmentId > 100 ? 100 : nextInvestmentId;
        for (uint256 i = 0; i < limitInv; i++) {
            Investment memory inv = investments[i];
            if (!inv.processed && !inv.earlyWithdrawn && block.timestamp >= inv.startTime + inv.duration) {
                return true;
            }
        }

        uint256 limitTrd = nextTradeId > 100 ? 100 : nextTradeId;
        for (uint256 j = 0; j < limitTrd; j++) {
            Trade memory trd = trades[j];
            if (!trd.processed && block.timestamp >= trd.startTime + trd.duration) {
                return true;
            }
        }
        return false;
    }

    function View_plans(address user, uint256 invCursor, uint256 invLimit, uint256 trdCursor, uint256 trdLimit) external view returns (
        UserGenData memory userData,
        Investment[] memory activeInvestments,
        Trade[] memory activeTrades
    ) {
        userData = UserGenData({
            counts: userGenCount[user],
            volumes: userGenVolume[user],
            totalEarnings: userTotalGenEarnings[user],
            referrer: referrerOf[user],
            directReferralCount: directReferrals[user].length,
            teamVolume: userTeamVolume[user],
            totalInvested: userTotalInvested[user]
        });

        activeInvestments = _getUserActiveInvestmentsPaged(user, invCursor, invLimit);
        activeTrades = _getUserActiveTradesPaged(user, trdCursor, trdLimit);
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
