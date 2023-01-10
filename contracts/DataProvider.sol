// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./libraries/LibFacet.sol";
import "./PriceFeed.sol";

contract DataProvider {
    using WadRayMath for uint256;

    struct GetUserGlobalDataVars {
        uint256 compoundedLiquidityBalance;
        uint256 compoundedBorrowBalance;
        uint256 originationFee;
        uint256 reserveDecimals;
        uint256 baseLTV;
        uint256 liquidationThreshold;
        uint256 tokenUnit;
        uint256 poolUnitPrice;
        uint256 liquidityBalanceETH;
        bool userUsesReserveAsCollateral;
        bool usageAsCollateralEnabled;
    }

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
        GetUserGlobalDataVars memory vars;
        LendingPoolCore core = LibFacet.getCore();
        address[] memory pools = core.getPools();
        for (uint256 poolIdx = 0; poolIdx < pools.length; poolIdx++) {
            (
                vars.compoundedLiquidityBalance,
                vars.compoundedBorrowBalance,
                vars.originationFee,
                vars.userUsesReserveAsCollateral
            ) = core.getUserPoolData(pools[poolIdx], _user);

            if (
                vars.compoundedBorrowBalance == 0 &&
                vars.compoundedLiquidityBalance == 0
            ) continue;

            (
                vars.reserveDecimals,
                vars.baseLTV,
                vars.liquidationThreshold,
                vars.usageAsCollateralEnabled
            ) = core.getPoolConfiguration(pools[poolIdx]);

            vars.tokenUnit = 10**vars.reserveDecimals;
            vars.poolUnitPrice = PriceFeed(
                LibFacet.facetStorage().dataFeedAddress
            ).getAssetPrice(pools[poolIdx]);

            if (vars.compoundedLiquidityBalance > 0) {
                vars.liquidityBalanceETH =
                    (vars.poolUnitPrice * vars.compoundedLiquidityBalance) /
                    vars.tokenUnit;
                totalLiquidityBalanceETH += vars.liquidityBalanceETH;

                if (
                    vars.usageAsCollateralEnabled &&
                    vars.userUsesReserveAsCollateral
                ) {
                    totalCollateralBalanceETH += vars.liquidityBalanceETH;
                    currentLTV += vars.liquidityBalanceETH * vars.baseLTV;
                    currentLiquidationThreshold +=
                        vars.liquidityBalanceETH *
                        vars.liquidationThreshold;
                }
            }

            if (vars.compoundedBorrowBalance > 0) {
                totalBorrowBalanceETH +=
                    (vars.poolUnitPrice * vars.compoundedBorrowBalance) /
                    vars.tokenUnit;
                totalFeesETH +=
                    (vars.originationFee * vars.poolUnitPrice) /
                    vars.tokenUnit;
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
        if (_totalBorrowBalanceETH == 0) return uint256(0);

        return
            ((_totalCollateralBalanceETH * _currentLiquidationThreshold) / 100)
                .wadDiv(_totalBorrowBalanceETH + _totalFeesETH);
    }
}
