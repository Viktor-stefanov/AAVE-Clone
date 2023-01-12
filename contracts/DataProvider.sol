// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./libraries/LibFacet.sol";
import "hardhat/console.sol";

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
        public
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
        LendingPoolCore core = LendingPoolCore(address(this));
        address[] memory pools = LibFacet.lpcStorage().allPools;
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
            vars.poolUnitPrice = LibFacet.getPriceFeed().getAssetPrice(
                pools[poolIdx]
            );

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
    ) internal pure returns (uint256) {
        if (_totalBorrowBalanceETH == 0) return type(uint256).max;

        return
            ((_totalCollateralBalanceETH * _currentLiquidationThreshold) / 100)
                .wadDiv(_totalBorrowBalanceETH + _totalFeesETH);
    }

    function calculateCollateralNeededInETH(
        address _pool,
        uint256 _amount,
        uint256 _fee,
        uint256 _userCurrentBorrowBalanceETH,
        uint256 _userCurrentFeesETH,
        uint256 _userCurrentLTV
    ) external view returns (uint256 collateralNeededInETH) {
        PriceFeed pf = LibFacet.getPriceFeed();

        uint256 poolDecimals = LendingPoolCore(address(this)).getPoolDecimals(
            _pool
        );
        uint256 requestedBorrowAmountETH = (pf.getAssetPrice(_pool) *
            (_amount + _fee)) / 10**poolDecimals;
        collateralNeededInETH =
            ((_userCurrentBorrowBalanceETH +
                _userCurrentFeesETH +
                requestedBorrowAmountETH) * 100) /
            _userCurrentLTV;
    }
}
