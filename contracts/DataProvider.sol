// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./libraries/LibFacet.sol";
import "./LendingPoolCore.sol";
import "./PriceFeed.sol";

contract DataProvider {
    /// @dev get user data accross all pools
    function getUserGlobalData(address _user)
        external
        view
        returns (
            uint256 totalLiquidityBalanceETH,
            uint256 totalCollateralBalanceETH,
            uint256 totalBorrowBalanceETH,
            uint256 totalFeesETH,
            uint256 currentLTV,
            uint256 currentLiquidationThreshold,
            uint256 healthFactor,
            bool healthFactorBelowThreshold
        )
    {
        address[] pools = LendingPoolCore.getPools();
        for (uint256 poolIdx = 0; poolIdx < pools.length; poolIdx++) {
            uint256 compoundedLiquidityBalance;
            uint256 compoundedBorrowBalance;
            uint256 originationFee;
            uint256 userUsesReserveAsCollateral;
            (
                compoundedLiquidityBalance,
                compoundedBorrowBalance,
                originationFee,
                userUsesReserveAsCollateral
            ) = LendingPoolCore.getUserPoolData(pools[poolIdx], _user);

            if (compoundedBorrowBalance == 0 && compoundedLiquidityBalance == 0)
                continue;

            uint256 reserveDecimals;
            uint256 baseLTV;
            uint256 liquidationThreshold;
            uint256 usageAsCollateralEnabled;
            (
                reserveDecimals,
                baseLTV,
                liquidationThreshold,
                usageAsCollateralEnabled
            ) = LendingPoolCore.getPoolConfiguration(pools[poolIdx]);

            uint256 tokenUnit = 10**reserveDecimals;
            uint256 reserveUnitPrice = PriceFeed(
                LibFacet.facetStorage().dataFeedAddress
            ).getAssetPrice(pools[poolIdx]);

            if (compoundedLiquidityBalance > 0) {
                uint256 liquidityBalanceETH = (reserveUnitPrice *
                    compoundedLiquidityBalance) / tokenUnit;
                totalLiquidityBalanceETH += liquidityBalanceETH;

                if (usageAsCollateralEnabled && userUsesReserveAsCollateral) {
                    totalCollateralBalanceETH += liquidityBalanceETH;
                    currentLTV += liquidityBalanceETH * baseLTV;
                    currentLiquidationThreshold +=
                        liquiditybalanceETH *
                        liquidationThreshold;
                }
            }

            if (compoundedBorrowBalance > 0) {
                totalBorrowBalanceETH +=
                    (reserveUnitPrice * compoundedBorrowBalance) /
                    tokenUnit;
                totalFeesETH += (originationFee * reserveUnitPrice) / tokenUnit;
            }
        }

        currentLTV = totalCollateralBalanceETH > 0
            ? currentLTV / totalCollateralBalanceETH
            : 0;
        currentLiquidationThreshold = totalCollateralBalanceETH > 0
            ? currentLiquidationThreshold / totalCollateralBalanceETH
            : 0;
        healthFactor = calculateHealthFactorFromBalances(
            totalCollateralBalanceETH,
            totalBorrowBalanceETH,
            totalFeesETH,
            currentLiquidationThreshold
        );
        healthFactorBelowThreshold = healthFactor < 1e18;
    }

    function calculateHealthFactorFromBalances(
        uint256 _totalCollateralBalanceETH,
        uint256 _totalBorrowBalanceETH,
        uint256 _totalFeesETH,
        uint256 _currentLiquidationThreshold
    ) internal view returns (uint256) {
        if (_totalBorrowBalanceETH == 0) return uint256(-1);

        return
            ((_totalCollateralBalanceETH * _currentLiquidationThreshold) / 100)
                .wadDiv(_totalBorrowBalanceETH + _totalFeesEth);
    }
}
