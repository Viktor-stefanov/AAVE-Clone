// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/LibFacet.sol";
import "./libraries/WadRayMath.sol";
import "hardhat/console.sol";

contract LendingPoolCore {
    using WadRayMath for uint256;

    function deposit(
        address _pool,
        address _user,
        uint256 _amount
    ) external payable {
        if (_pool == LibFacet.facetStorage().ethAddress)
            return depositEth(_pool, _user, _amount);

        require(
            ERC20(_pool).balanceOf(_user) >= _amount,
            "Insufficient token balance."
        );
        updatePoolOnDeposit(_pool, _amount);
        ERC20(_pool).transferFrom(_user, address(this), _amount);
    }

    function depositEth(
        address _pool,
        address _user,
        uint256 _amount
    ) internal {
        require(_user.balance >= _amount, "Insufficient ETH balance.");
        updatePoolOnDeposit(_pool, _amount);
        (bool success, ) = _user.call{value: _amount}("");
        require(success, "Error while sending eth.");
    }

    function redeem(
        address _pool,
        address _user,
        uint256 _amount
    ) external {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        require(
            pool.user[_user].liquidityProvided >= _amount,
            "Can't redeem more than has been deposited."
        );
        require(
            pool.totalLiquidity >= _amount,
            "Pool does not have enough resources at the current moment."
        );
        updateCumulativeIndexes(pool);
        uint256 ethAmount = getEthValue(_pool, _amount);
        require(
            getHealthFactor(
                pool.user[_user].collateralEthBalance - ethAmount,
                pool.user[_user].liquidationThreshold,
                pool.user[_user].compoundedBorrowBalance
            ) > 1,
            "Cannot redeem as it will cause your loan health factor to drop below 1."
        );
        pool.user[_user].collateralEthBalance -= ethAmount;
        pool.user[_user].liquidityProvided -= _amount;
        pool.totalLiquidity -= _amount;
        updatePoolInterestRates(pool);
        if (_pool == LibFacet.facetStorage().ethAddress) {
            (bool success, ) = _user.call{value: _amount}("");
            require(success, "Error transfering ETH.");
        } else ERC20(_pool).transferFrom(address(this), _user, _amount);
    }

    function borrow(
        address _pool,
        address _user,
        uint256 _amount
    ) external payable {}

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

    function updatePoolOnDeposit(address _pool, uint256 _amount) internal {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        testPrint(pool);
        updateCumulativeIndexes(pool);
        pool.totalLiquidity += _amount;
        updatePoolInterestRates(pool);
        testPrint(pool);
        pool.user[msg.sender].liquidityProvided += _amount;
    }

    function updateStateOnBorrow(
        LibFacet.Pool storage _pool,
        address _user,
        address _borrowedAsset,
        uint256 _amount
    ) internal returns (uint256, uint256) {
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
            _amountBorrowed,
            _rateMode
        );

        updateUserStateOnBorrow(
            _pool,
            _user,
            _amountBorrowed,
            balanceIncrease,
            _borrowFee,
            _rateMode
        );

        updatePoolInterestRates(_pool, 0, _amountBorrowed);
    }

    function updatePoolStateOnBorrow(
        LibFacet.Pool storage _pool,
        address _user,
        uint256 _principalBorrowBalance,
        uint256 _balanceIncrease,
        uint256 _amountBorrowed,
        LibFacet.InterestRateMode _rateMode
    ) internal {
        updateCumulativeIndexes(_pool);
        updatePoolTotalBorrows(
            _pool,
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
            user.rates.cumulativeVariableBorrowIndex = pool
                .rates
                .cumulatedVariableBorrowIndex;
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
    ) {
        LibFacet.InterestRateMode previousRateMode = getUserCurrentBorrowRateMode(
                _pool.user[_user]
            );
        if (previousRateMode == LibFacet.InterestRateMode.STABLE) {} else if (
            previousRateMode == LibFacet.InterestRateMode.VARIABLE
        ) {
            decreaseTotalVariableBorrows(_principalBorrowBalance);
        }

        uint256 newPrincipalAmount = _principalBorrowBalance +
            _amountBorrowed +
            _balanceIncrease;
        if (_newRateMode == LibFacet.InterestRateMode.STABLE) {} else if (
            previousRateMode == LibFacet.InterestRateMode.VARIABLE
        ) {
            increaseTotalVariableBorrows(newPrincipalAmount);
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
    ) {
        _pool.totalVariableBorrowLiquidity += _amount;
    }

    function getUserCurrentBorrowRateMode(LibFacet.UserPoolData _user)
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
            ).rayMul(_pool.cumulatedLiquidityIndex);
            _pool.cumulatedVariableBorrowIndex = calculateCompoundedInterest(
                _pool.rates.variableBorrowRate,
                LibFacet.lpcStorage().SECONDS_IN_YEAR,
                block.timestamp,
                _pool.lastUpdatedTimestamp
            ).rayMul(_pool.cumulatedVariableBorrowIndex);
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
            _pool.totalLiquidity,
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
        view
        returns (
            uint256 currentVariableBorrowRate,
            uint256 currentLiquidityRate
        )
    {
        uint256 totalBorrows = _totalVariableBorrows; /// @dev + totalStableBorrows
        uint256 utilizationRate = (_totalLiquidity == 0 && totalBorrows == 0)
            ? 0
            : totalBorrows / _totalLiquidity;
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
        );
    }

    function calculateOverallBorrowRate(
        uint256 _totalVariableBorrows,
        uint256 _currentVariableBorrowRate
    ) internal pure returns (uint256) {
        uint256 totalBorrows = _totalVariableBorrows; /// TODO: + _totalStableBorrows
        if (totalBorrows == 0) return 0;

        uint256 weightedVariableRate = _totalVariableBorrows.wadToRay().rayDiv(
            _currentVariableBorrowRate
        );

        return weightedVariableRate.rayDiv(totalBorrows.wadToRay());
    }

    function getUserBorrowBalances(LibFacet.Pool storage _pool, address _user)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        LibFacet.UserPoolData storage user = _pool.user[_user];
        if (user.principalBorrowBalance == 0) return (0, 0, 0);

        uint256 compoundedBalance = getCompoundedBorrowBalance(user, _pool);
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

        if (_user.rate.stableBorrowRate > 0) {} else {
            // variable interest
            cumulatedInterest = calculateCompoundedInterest(
                _pool.currentVariableBorrowRate,
                _pool.lastUpdatedTimestamp
            ).rayMul(_pool.cumulatedVariableBorrowIndex).rayDiv(
                    _user.cumulatedVariableBorrowIndex
                );
        }

        compoundedBalance = principalBorrowBalance
            .rayMul(cumulatedInterest)
            .rayToWad();
        if (compoundedBalance == _user.principalBorrowBalance)
            if (_user.lastUpdatedTimestamp != block.timestamp)
                return _user.princiapBorrowBalance + 1 wei;

        return compoundedBalance;
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
        LibFacet.Pool storage pool = LibFacet.lcpStorage().pools[_pool];
        uint256 assetBalance = pool.user[_user].liquidityProvided;
        if (pool.user[_user].principalBorrowBalance == 0)
            return (assetBalance, 0, 0, pool.user[_user].userAsCollateral);
        return (
            assetBalance,
            getCompoundedBorrowBalance(_user, _pool),
            pool.user[_user].originationFee,
            pool.user[_user].userAsCollateral
        );
    }

    function getPoolConfiguration(address _pool)
        external
        view
        returns (
            uint256 reserveDecimals,
            uint256 baseLTV,
            uint256 liquidationTHreshold,
            uint256 usageAsCollateralEnabled
        )
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        return (
            pool.decimals,
            pool.baseLTV,
            pool.liquidationThreshold,
            pool.usageAsCollateralEnabled
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
}
