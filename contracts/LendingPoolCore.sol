// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./libraries/LibFacet.sol";
import "./libraries/WadRayMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract LendingPoolCore {
    using WadRayMath for uint256;

    function getEthValue(address _token, uint256 _amount)
        internal
        view
        returns (uint256)
    {
        uint256 loanToValue = LibFacet.lpcStorage().pools[_token].loanToValue;
        return ((_amount * loanToValue) / 100);
    }

    function testPrint(LibFacet.Pool storage pool) internal view {
        console.log(pool.cumulatedLiquidityIndex);
        console.log(pool.rates.variableBorrowRate);
    }

    function updateStateOnDeposit(
        address _pool,
        address _user,
        uint256 _amount
    ) public {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        testPrint(pool);
        updateCumulativeIndexes(pool);
        updatePoolInterestRates(pool, _amount, 0);
        pool.totalLiquidity += _amount;
        pool.user[_user].liquidityProvided += _amount;
        testPrint(pool);
    }

    function updateStateOnRedeem(
        address _pool,
        address _user,
        uint256 _amount
    ) public {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        updateCumulativeIndexes(pool);
        updatePoolInterestRates(pool, 0, _amount);
        pool.totalLiquidity -= _amount;
        pool.user[_user].liquidityProvided -= _amount;
    }

    function updateStateOnBorrow(
        address _pool,
        address _user,
        uint256 _amount,
        uint256 _borrowFee,
        LibFacet.InterestRateMode _rateMode
    ) public returns (uint256, uint256) {
        (
            uint256 principalBorrowBalance,
            ,
            uint256 balanceIncrease
        ) = getUserBorrowBalances(_pool, _user);

        updatePoolStateOnBorrow(
            _pool,
            _user,
            principalBorrowBalance,
            balanceIncrease,
            _amount,
            _rateMode
        );

        updateUserStateOnBorrow(
            _pool,
            _user,
            _amount,
            balanceIncrease,
            _borrowFee,
            _rateMode
        );

        updatePoolInterestRates(LibFacet.lpcStorage().pools[_pool], 0, _amount);

        return (getUserCurrentBorrowRate(_pool, _user), balanceIncrease);
    }

    function updatePoolStateOnBorrow(
        address _pool,
        address _user,
        uint256 _principalBorrowBalance,
        uint256 _balanceIncrease,
        uint256 _amountBorrowed,
        LibFacet.InterestRateMode _rateMode
    ) internal {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        updateCumulativeIndexes(pool);
        updatePoolTotalBorrows(
            pool,
            _user,
            _principalBorrowBalance,
            _balanceIncrease,
            _amountBorrowed,
            _rateMode
        );
    }

    /// TODO: ADD previous values of indexes to the Pool and UserPoolData structs.
    function updateUserStateOnBorrow(
        address _pool,
        address _user,
        uint256 _amountBorrowed,
        uint256 _balanceIncrease,
        uint256 _fee,
        LibFacet.InterestRateMode _rateMode
    ) internal {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        LibFacet.UserPoolData storage user = pool.user[_user];

        if (_rateMode == LibFacet.InterestRateMode.STABLE) {} else if (
            _rateMode == LibFacet.InterestRateMode.VARIABLE
        ) {
            user.rates.stableBorrowRate = 0;

            user.lastCumulatedVariableBorrowIndex = pool
                .lastCumulatedVariableBorrowIndex;
        } else {
            revert("Invalid borrow mode.");
        }

        user.principalBorrowBalance += _balanceIncrease + _amountBorrowed;
        user.originationFee = user.originationFee + _fee;
        user.lastUpdatedTimestamp = block.timestamp;
    }

    function updatePoolTotalBorrows(
        LibFacet.Pool storage _pool,
        address _user,
        uint256 _principalBorrowBalance,
        uint256 _balanceIncrease,
        uint256 _amountBorrowed,
        LibFacet.InterestRateMode _newRateMode
    ) internal {
        LibFacet.InterestRateMode previousRateMode = getUserCurrentBorrowRateMode(
                _pool.user[_user]
            );
        if (previousRateMode == LibFacet.InterestRateMode.STABLE) {} else if (
            previousRateMode == LibFacet.InterestRateMode.VARIABLE
        ) {
            decreaseTotalVariableBorrows(_pool, _principalBorrowBalance);
        }

        uint256 newPrincipalAmount = _principalBorrowBalance +
            _amountBorrowed +
            _balanceIncrease;
        if (_newRateMode == LibFacet.InterestRateMode.STABLE) {} else if (
            previousRateMode == LibFacet.InterestRateMode.VARIABLE
        ) {
            increaseTotalVariableBorrows(_pool, newPrincipalAmount);
        } else {
            revert("Invalid new borrow rate mode.");
        }
    }

    function decreaseTotalVariableBorrows(
        LibFacet.Pool storage _pool,
        uint256 _amount
    ) internal {
        require(
            _pool.totalVariableBorrowLiquidity >= _amount,
            "The amount that is being subtracted from the variable borrows is incorrect."
        );
        _pool.totalVariableBorrowLiquidity -= _amount;
    }

    function increaseTotalVariableBorrows(
        LibFacet.Pool storage _pool,
        uint256 _amount
    ) internal {
        _pool.totalVariableBorrowLiquidity += _amount;
    }

    function getUserCurrentBorrowRateMode(LibFacet.UserPoolData storage _user)
        internal
        view
        returns (LibFacet.InterestRateMode)
    {
        if (_user.principalBorrowBalance == 0)
            return LibFacet.InterestRateMode.NONE;

        return
            _user.rates.stableBorrowRate > 0
                ? LibFacet.InterestRateMode.STABLE
                : LibFacet.InterestRateMode.VARIABLE;
    }

    function updateCumulativeIndexes(LibFacet.Pool storage _pool) internal {
        if (_pool.totalBorrowedLiquidity > 0) {
            _pool.cumulatedLiquidityIndex = calculateLinearInterest(
                _pool.rates.currentLiquidityRate,
                _pool.lastUpdatedTimestamp
            ).rayMul(_pool.lastCumulatedLiquidityIndex);
            _pool.cumulatedVariableBorrowIndex = calculateCompoundedInterest(
                _pool.rates.variableBorrowRate,
                LibFacet.lpcStorage().SECONDS_IN_YEAR,
                block.timestamp,
                _pool.lastUpdatedTimestamp
            ).rayMul(_pool.lastCumulatedVariableBorrowIndex);
        }
    }

    function updatePoolInterestRates(
        LibFacet.Pool storage _pool,
        uint256 _liquidityAdded,
        uint256 _liquidityTaken
    ) internal {
        (
            _pool.rates.variableBorrowRate,
            _pool.rates.currentLiquidityRate
        ) = calculateInterestRates(
            _pool.totalLiquidity + _liquidityAdded - _liquidityTaken,
            _pool.totalVariableBorrowLiquidity,
            _pool.rates.interestRateSlopeBelow,
            _pool.rates.interestRateSlopeAbove,
            _pool.rates.baseVariableBorrowRate,
            _pool.rates.targetUtilisationRate
        );
        _pool.lastUpdatedTimestamp = block.timestamp;
    }

    function calculateInterestRates(
        uint256 _totalLiquidity,
        uint256 _totalVariableBorrows,
        uint256 _variableRateSlope1,
        uint256 _VariableRateSlope2,
        uint256 _baseVariableBorrowRate,
        uint256 _optimalUtilizationRate
    )
        internal
        pure
        returns (
            uint256 currentVariableBorrowRate,
            uint256 currentLiquidityRate
        )
    {
        uint256 totalBorrows = _totalVariableBorrows; /// @dev + totalStableBorrows
        uint256 utilizationRate = (_totalLiquidity == 0 && totalBorrows == 0)
            ? 0
            : totalBorrows.rayDiv(_totalLiquidity);
        if (utilizationRate > _optimalUtilizationRate) {
            uint256 excessUtilizationRateRatio = (utilizationRate -
                _optimalUtilizationRate).rayDiv(1 - _optimalUtilizationRate);
            currentVariableBorrowRate =
                _baseVariableBorrowRate +
                _variableRateSlope1 +
                (_VariableRateSlope2.rayMul(excessUtilizationRateRatio));
        } else {
            currentVariableBorrowRate =
                _baseVariableBorrowRate +
                (
                    utilizationRate.rayDiv(_optimalUtilizationRate).rayMul(
                        _variableRateSlope1
                    )
                );
        }
        currentLiquidityRate = calculateOverallBorrowRate(
            _totalVariableBorrows,
            currentVariableBorrowRate
        ).rayMul(utilizationRate);
    }

    function calculateOverallBorrowRate(
        uint256 _totalVariableBorrows,
        uint256 _currentVariableBorrowRate
    ) internal pure returns (uint256) {
        uint256 totalBorrows = _totalVariableBorrows; /// TODO: + _totalStableBorrows
        if (totalBorrows == 0) return 0;

        uint256 weightedVariableRate = _totalVariableBorrows.wadToRay().rayMul(
            _currentVariableBorrowRate
        );

        return weightedVariableRate.rayDiv(totalBorrows.wadToRay());
    }

    function getUserBorrowBalances(address _pool, address _user)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        LibFacet.UserPoolData storage user = pool.user[_user];
        if (user.principalBorrowBalance == 0) return (0, 0, 0);

        uint256 compoundedBalance = getCompoundedBorrowBalance(user, pool);
        return (
            user.principalBorrowBalance,
            compoundedBalance,
            compoundedBalance - user.principalBorrowBalance
        );
    }

    /// @dev calculates interest using compounded interest rate formula
    function calculateCompoundedInterest(
        uint256 _variableBorrowRate,
        uint256 _secondsInAYear,
        uint256 _timestamp,
        uint256 _lastUpdatedTimestamp
    ) internal pure returns (uint256) {
        uint256 ratePerSecond = _variableBorrowRate.rayDiv(_secondsInAYear);
        return
            ratePerSecond +
            (WadRayMath.RAY.rayPow(_timestamp - _lastUpdatedTimestamp));
    }

    /// @dev calculates interest using linear interest rate formula
    function calculateLinearInterest(
        uint256 _currentLiquidityRate,
        uint256 _lastUpdatedTimestamp
    ) internal view returns (uint256) {
        uint256 timeDelta = calculateTimeDelta(
            block.timestamp,
            _lastUpdatedTimestamp,
            LibFacet.lpcStorage().SECONDS_IN_YEAR
        );
        return _currentLiquidityRate.rayMul(timeDelta) + WadRayMath.RAY;
    }

    function calculateTimeDelta(
        uint256 _timestamp,
        uint256 _lastUpdatedTimestamp,
        uint256 _secondsInAYear
    ) internal pure returns (uint256) {
        return
            (_timestamp - _lastUpdatedTimestamp).wadToRay().rayDiv(
                _secondsInAYear.wadToRay()
            );
    }

    function calculateAvailableLiquidity(LibFacet.Pool storage pool)
        internal
        view
        returns (uint256)
    {
        return pool.totalLiquidity - pool.totalBorrowedLiquidity;
    }

    function getCompoundedBorrowBalance(
        LibFacet.UserPoolData storage _user,
        LibFacet.Pool storage _pool
    ) internal view returns (uint256) {
        if (_user.principalBorrowBalance == 0) return 0;

        uint256 principalBorrowBalance = _user
            .principalBorrowBalance
            .wadToRay();
        uint256 compoundedBalance = 0;
        uint256 cumulatedInterest = 0;

        if (_user.rates.stableBorrowRate > 0) {} else {
            // variable interest
            cumulatedInterest = calculateCompoundedInterest(
                _pool.rates.variableBorrowRate,
                LibFacet.lpcStorage().SECONDS_IN_YEAR,
                block.timestamp,
                _pool.lastUpdatedTimestamp
            ).rayMul(_pool.lastCumulatedVariableBorrowIndex).rayDiv(
                    _user.lastCumulatedVariableBorrowIndex
                );
        }

        compoundedBalance = principalBorrowBalance
            .rayMul(cumulatedInterest)
            .rayToWad();

        if (compoundedBalance == _user.principalBorrowBalance)
            if (_user.lastUpdatedTimestamp != block.timestamp)
                return _user.principalBorrowBalance + 1 wei;

        return compoundedBalance;
    }

    function getUserCurrentBorrowRate(address _pool, address _user)
        internal
        view
        returns (uint256)
    {
        LibFacet.InterestRateMode rateMode = getUserCurrentBorrowRateMode(
            _pool,
            _user
        );

        if (rateMode == LibFacet.InterestRateMode.NONE) return 0;

        return
            rateMode == LibFacet.InterestRateMode.STABLE
                ? 0
                : LibFacet.lpcStorage().pools[_pool].rates.variableBorrowRate;
    }

    function getUserCurrentBorrowRateMode(address _pool, address _user)
        internal
        view
        returns (LibFacet.InterestRateMode)
    {
        return LibFacet.lpcStorage().pools[_pool].user[_user].rates.rateMode;
    }

    function getUserPoolData(address _pool, address _user)
        external
        view
        returns (
            uint256 compoundedLiquidityBalance,
            uint256 compoundedBorrowBalance,
            uint256 originationFee,
            bool userUsesPoolAsCollateral
        )
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        uint256 assetBalance = pool.user[_user].liquidityProvided;
        if (pool.user[_user].principalBorrowBalance == 0)
            return (assetBalance, 0, 0, pool.user[_user].useAsCollateral);
        return (
            assetBalance,
            getCompoundedBorrowBalance(pool.user[_user], pool),
            pool.user[_user].originationFee,
            pool.user[_user].useAsCollateral
        );
    }

    function getPoolConfiguration(address _pool)
        external
        view
        returns (
            uint256 reserveDecimals,
            uint256 baseLTV,
            uint256 liquidationTHreshold,
            bool usageAsCollateralEnabled
        )
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        return (
            pool.decimals,
            pool.baseLTV,
            pool.liquidationThreshold,
            pool.isUsableAsCollateral
        );
    }

    function getPools() external view returns (address[] memory) {
        return LibFacet.lpcStorage().allPools;
    }

    function getHealthFactor(
        uint256 _collateralEth,
        uint256 _liquidationThreshold,
        uint256 _compoundedBorrowBalance
    ) internal pure returns (uint256) {
        return
            _collateralEth.rayMul(_liquidationThreshold).rayDiv(
                _compoundedBorrowBalance
            );
    }

    function getPoolDecimals(address _pool) public view returns (uint256) {
        return LibFacet.lpcStorage().pools[_pool].decimals;
    }

    function getPoolAvailableLiquidity(address _pool)
        public
        view
        returns (uint256)
    {
        return LibFacet.lpcStorage().pools[_pool].totalLiquidity;
    }

    function isPoolBorrowingEnabled(address _pool) public view returns (bool) {
        return LibFacet.lpcStorage().pools[_pool].isBorrowingEnabled;
    }

    function isPoolUsageAsCollateralEnabled(address _pool)
        public
        view
        returns (bool)
    {
        return LibFacet.lpcStorage().pools[_pool].isUsableAsCollateral;
    }

    function transferToPool(
        address _pool,
        address _user,
        uint256 _amount
    ) public payable {
        if (_pool == LibFacet.facetStorage().ethAddress) {
            (bool success, ) = _pool.call{value: _amount}("");
            require(success, "Error while sending ETH.");
        } else {
            ERC20(_pool).transferFrom(_user, _pool, _amount);
        }
    }

    function transferToUser(
        address _pool,
        address _user,
        uint256 _amount
    ) public {
        if (_pool == LibFacet.facetStorage().ethAddress) {
            (bool success, ) = _user.call{value: _amount}("");
            require(success, "Error while sending ETH.");
        } else {
            ERC20(_pool).transferFrom(_pool, _user, _amount);
        }
    }
}
