// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "../libraries/LibFacet.sol";
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
            ) = core.getUserBasicPoolData(pools[poolIdx], _user);

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
                /// @dev totalLiquidityBalanceETH is the equivalent asset in US dollars. So 0.5 compoundedLiquidityBalance will yield 750 totalLiquidtiyBalacneETH if price for 1 ETH = 1500
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

        /// TODO: aren't the currentLTV and currentLiquidationThreshold always equal to baseLTV and liquidationThreshold?
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

    function getUserPoolData(address _pool, address _user)
        public
        view
        returns (
            uint256 currentBorrowBalance,
            uint256 principalBorrowBalance,
            uint256 liquidityRate,
            uint256 originationFee,
            uint256 variableBorrowIndex,
            uint256 lastUpdatedTimestamp,
            LibFacet.InterestRateMode borrowRateMode,
            bool usageAsCollateralEnabled
        )
    {
        LendingPoolCore core = LendingPoolCore(address(this));
        (principalBorrowBalance, currentBorrowBalance, ) = core
            .getUserBorrowBalances(_pool, _user);
        borrowRateMode = core.getUserCurrentBorrowRateMode(_pool, _user);
        liquidityRate = core.getPoolLiquidityRate(_pool);
        originationFee = core.getUserOriginationFee(_pool, _user);
        variableBorrowIndex = core.getUserVariableBorrowIndex(_pool, _user);
        lastUpdatedTimestamp = core.getUserLastUpdatedTimestamp(_pool, _user);
        usageAsCollateralEnabled = core.getUserUsePoolAsCollateral(
            _pool,
            _user
        );
    }

    function getUserRewardShare(address _pool, address _user)
        public
        view
        returns (uint256)
    {
        uint256 liquidityProvidedByUser = LibFacet
            .lpcStorage()
            .pools[_pool]
            .users[_user]
            .liquidityProvided;
        if (liquidityProvidedByUser == 0) return 0;

        uint256 totalLiquidityProvided = 0;
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        for (uint256 userIdx = 0; userIdx < pool.allUsers.length; userIdx++)
            totalLiquidityProvided += pool
                .users[pool.allUsers[userIdx]]
                .liquidityProvided;

        return liquidityProvidedByUser.wadDiv(totalLiquidityProvided);
    }

    function getAllActivePools() external view returns (address[] memory) {
        address[] memory allPools = LibFacet.lpcStorage().allPools;
        address[] memory activePools = new address[](allPools.length);
        uint256 activePoolIndex = 0;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (LibFacet.lpcStorage().pools[allPools[i]].isActive)
                activePools[activePoolIndex++] = allPools[i];
        }

        return activePools;
    }

    function getAllActivePoolAssetNames()
        external
        view
        returns (string[] memory)
    {
        address[] memory allPools = LibFacet.lpcStorage().allPools;
        string[] memory activePools = new string[](allPools.length);
        uint256 activePoolIndex = 0;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (LibFacet.lpcStorage().pools[allPools[i]].isActive)
                activePools[activePoolIndex++] = LibFacet
                    .lpcStorage()
                    .pools[allPools[i]]
                    .asset;
        }

        return activePools;
    }

    function getPoolDisplayData(address _pool)
        external
        view
        returns (
            string memory asset,
            uint256 loanToValue,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 depositedLiquidity,
            uint256 borrowedLiquidity,
            bool isBorrowingEnabled,
            bool isUsableAsCollateral,
            bool isActive
        )
    {
        return LendingPoolCore(address(this)).getPoolDisplayInformation(_pool);
    }

    function getPoolDepositData(address _pool)
        external
        view
        returns (
            string memory asset,
            uint256 depositedLiquidity,
            uint256 borrowedLiquidity,
            uint256 depositAPY,
            bool isUsableAsCollateral
        )
    {
        (
            asset,
            depositedLiquidity,
            borrowedLiquidity,
            isUsableAsCollateral
        ) = LendingPoolCore(address(this)).getPoolDepositInformation(_pool);
        depositAPY = LendingPoolCore(address(this)).calculateUserDepositAPY(
            _pool
        );
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

    function calculateAvailableBorrowsETH(address _user)
        public
        view
        returns (uint256)
    {
        (
            ,
            uint256 collateralBalanceETH,
            uint256 borrowBalanceETH,
            uint256 totalFeesETH,
            uint256 LTV,
            ,
            ,

        ) = getUserGlobalData(_user);

        return
            calculateAvailableBorrowsETHInternal(
                collateralBalanceETH,
                borrowBalanceETH,
                totalFeesETH,
                LTV
            );
    }

    function calculateAvailableBorrowsETHInternal(
        uint256 _collateralBalanceETH,
        uint256 _borrowBalanceETH,
        uint256 _totalFeesETH,
        uint256 _LTV
    ) internal view returns (uint256) {
        uint256 availableBorrowsETH = (_collateralBalanceETH * _LTV) / 100;
        if (availableBorrowsETH <= _borrowBalanceETH) return 0;

        availableBorrowsETH -= _borrowBalanceETH + _totalFeesETH;

        uint256 originationFee = FeeProvider(address(this))
            .calculateLoanOriginationFee(availableBorrowsETH);
        return availableBorrowsETH - originationFee;
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
