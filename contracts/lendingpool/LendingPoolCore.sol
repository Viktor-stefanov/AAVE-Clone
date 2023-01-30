// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./DataProvider.sol";
import "../libraries/LibFacet.sol";
import "../libraries/WadRayMath.sol";
import "../mocks/EthMock.sol";
import "../mocks/UsdcMock.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

// @TODO rename _balanceIncrease to something like "accumulatedInterest"
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

    function updateStateOnDeposit(
        address _pool,
        address _user,
        uint256 _amount,
        bool _useAsCollateral
    ) public {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        updateCumulativeIndexes(pool);
        updatePoolInterestRates(pool, _amount, 0);
        bool isFirstDeposit = pool.users[_user].liquidityProvided == 0;
        pool.providedLiquidity += _amount;
        pool.users[_user].liquidityProvided += _amount;
        setUserUsePoolAsCollateralInternal(_pool, _user, _useAsCollateral);
        if (isFirstDeposit) {
            pool.allUsers.push(_user);
            initializeUserData(pool.users[_user]);
        }
    }

    function updateStateOnRedeem(
        address _pool,
        address _user,
        uint256 _amount,
        bool _userRedeemedEverything
    ) public {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        updateCumulativeIndexes(pool);

        uint256 liquidityProvided = pool.users[_user].liquidityProvided;
        if (_amount > liquidityProvided) {
            updatePoolInterestRates(pool, 0, liquidityProvided);
            pool.users[_user].liquidityProvided = 0;
            pool.providedLiquidity -= liquidityProvided;
            pool.rewardsLiquidity -= (_amount - liquidityProvided);
        } else {
            updatePoolInterestRates(pool, 0, _amount);
            pool.providedLiquidity -= _amount;
            pool.users[_user].liquidityProvided -= _amount;
        }

        if (_userRedeemedEverything) {
            setUserUsePoolAsCollateralInternal(_pool, _user, false);
            pool.users[_user].rates.variableBorrowRate = 0;
            pool.users[_user].rates.stableBorrowRate = 0;
            pool.users[_user].rates.stableBorrowRate = 0;
            pool.users[_user].rates.cumulatedVariableBorrowIndex =
                1 *
                WadRayMath.RAY;
        }
    }

    function updateStateOnBorrow(
        address _pool,
        address _user,
        uint256 _amount,
        uint256 _borrowFee,
        LibFacet.InterestRateMode _rateMode
    ) public {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        LibFacet.UserPoolData storage user = pool.users[_user];
        (
            uint256 principalBorrowBalance,
            ,
            uint256 balanceIncrease
        ) = getUserBorrowBalances(_pool, _user);

        updatePoolStateOnBorrow(
            pool,
            _user,
            principalBorrowBalance,
            balanceIncrease,
            _amount,
            _rateMode
        );

        updateUserStateOnBorrow(
            pool,
            user,
            _amount,
            balanceIncrease,
            _borrowFee,
            _rateMode
        );

        updatePoolInterestRates(pool, 0, _amount);
    }

    function updateStateOnRepay(
        address _pool,
        address _user,
        uint256 _paybackAmountMinusFee,
        uint256 _originationFeeRepaid,
        uint256 _balanceIncrease,
        bool _repaidWholeLoan
    ) external {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];

        updatePoolStateOnRepay(
            pool,
            _pool,
            _user,
            _paybackAmountMinusFee,
            _balanceIncrease
        );
        updateUserStateOnRepay(
            pool,
            _user,
            _paybackAmountMinusFee,
            _originationFeeRepaid,
            _balanceIncrease,
            _repaidWholeLoan
        );

        updatePoolInterestRates(pool, _paybackAmountMinusFee, 0);
    }

    function updateStateOnLiquidationCall(
        address _pool,
        address _collateral,
        address _user,
        uint256 _principalAmountToRepay,
        uint256 _feeRepayed,
        uint256 _collateralAmountToLiquidate,
        uint256 _balanceIncrease
    ) public {
        LibFacet.Pool storage principalPool = LibFacet.lpcStorage().pools[
            _pool
        ];
        LibFacet.Pool storage collateralPool = LibFacet.lpcStorage().pools[
            _collateral
        ];

        updatePrincipalPoolStateOnLiquidationCall(
            principalPool,
            principalPool.users[_user],
            _principalAmountToRepay,
            _balanceIncrease
        );
        updateCumulativeIndexes(collateralPool);
        updateUserStateOnLiquidationCall(
            principalPool,
            collateralPool,
            _user,
            _principalAmountToRepay,
            _feeRepayed,
            _balanceIncrease,
            _collateralAmountToLiquidate
        );
        updatePoolInterestRates(principalPool, _principalAmountToRepay, 0);
        updatePoolInterestRates(
            collateralPool,
            0,
            _collateralAmountToLiquidate
        );
    }

    function updateUserStateOnLiquidationCall(
        LibFacet.Pool storage _pool,
        LibFacet.Pool storage _collateral,
        address _user,
        uint256 _amountRepayed,
        uint256 _feeLiquidated,
        uint256 _balanceIncrease,
        uint256 _collateralToLiquidate
    ) internal {
        _collateral.users[_user].liquidityProvided -= _collateralToLiquidate;
        _pool.users[_user].principalBorrowBalance -=
            _amountRepayed -
            _balanceIncrease;
        _pool.users[_user].originationFee -= _feeLiquidated;
        if (
            _pool.users[_user].rates.rateMode ==
            LibFacet.InterestRateMode.VARIABLE
        )
            _pool.users[_user].cumulatedVariableBorrowIndex = _pool
                .cumulatedVariableBorrowIndex;
        _pool.users[_user].lastUpdatedTimestamp = block.timestamp;
    }

    function updatePrincipalPoolStateOnLiquidationCall(
        LibFacet.Pool storage _pool,
        LibFacet.UserPoolData storage _user,
        uint256 _amountToRepay,
        uint256 _balanceIncrease
    ) internal {
        console.log(_pool.borrowedLiquidity);
        console.log(_amountToRepay);
        console.log(_balanceIncrease);
        _pool.borrowedLiquidity -= _amountToRepay - _balanceIncrease;
        updateCumulativeIndexes(_pool);
        if (
            _user.rates.rateMode == LibFacet.InterestRateMode.STABLE
        ) {} else if (
            _user.rates.rateMode == LibFacet.InterestRateMode.VARIABLE
        ) {
            increaseTotalVariableBorrows(_pool, _balanceIncrease);
            decreaseTotalVariableBorrows(_pool, _amountToRepay);
        }
    }

    function updatePoolStateOnLiquidationCall(
        LibFacet.Pool storage _pool,
        uint256 _amount,
        uint256 _balanceIncrease,
        LibFacet.InterestRateMode _interestMode
    ) internal {
        updateCumulativeIndexes(_pool);
        _pool.providedLiquidity += _balanceIncrease;
        if (_interestMode == LibFacet.InterestRateMode.STABLE) {} else if (
            _interestMode == LibFacet.InterestRateMode.VARIABLE
        ) {
            decreaseTotalVariableBorrows(_pool, _amount);
        }
    }

    function updatePoolStateOnRepay(
        LibFacet.Pool storage _pool,
        address _poolAddress,
        address _user,
        uint256 _paybackAmountMinusFee,
        uint256 _balanceIncrease
    ) internal {
        updateCumulativeIndexes(_pool);
        _pool.rewardsLiquidity += _balanceIncrease;
        _pool.borrowedLiquidity -= _paybackAmountMinusFee - _balanceIncrease;

        LibFacet.InterestRateMode borrowMode = getUserCurrentBorrowRateMode(
            _poolAddress,
            _user
        );
        if (borrowMode == LibFacet.InterestRateMode.VARIABLE) {
            increaseTotalVariableBorrows(_pool, _balanceIncrease);
            decreaseTotalVariableBorrows(_pool, _paybackAmountMinusFee);
        } else {}
    }

    function updateUserStateOnRepay(
        LibFacet.Pool storage _pool,
        address _user,
        uint256 _paybackAmountMinusFee,
        uint256 _originationFeeRepaid,
        uint256 _balanceIncrease,
        bool _repaidWholeLoan
    ) internal {
        LibFacet.UserPoolData storage user = _pool.users[_user];
        user.principalBorrowBalance -=
            _paybackAmountMinusFee -
            _balanceIncrease;
        user.cumulatedVariableBorrowIndex = _pool.cumulatedVariableBorrowIndex;
        if (_repaidWholeLoan) {
            user.rates.stableBorrowRate = 0;
            user.rates.variableBorrowRate = 0;
        }
        user.originationFee = user.originationFee - _originationFeeRepaid;
        user.lastUpdatedTimestamp = block.timestamp;
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
        _pool.borrowedLiquidity += _amountBorrowed;
    }

    // TODO: ADD previous values of indexes to the Pool and UserPoolData structs.
    function updateUserStateOnBorrow(
        LibFacet.Pool storage _pool,
        LibFacet.UserPoolData storage _user,
        uint256 _amountBorrowed,
        uint256 _balanceIncrease,
        uint256 _fee,
        LibFacet.InterestRateMode _rateMode
    ) internal {
        if (_rateMode == LibFacet.InterestRateMode.STABLE) {} else if (
            _rateMode == LibFacet.InterestRateMode.VARIABLE
        ) {
            _user.rates.stableBorrowRate = 0;
            _user.cumulatedVariableBorrowIndex = _pool
                .cumulatedVariableBorrowIndex;
        } else {
            revert("Invalid borrow mode.");
        }

        _user.principalBorrowBalance += _balanceIncrease + _amountBorrowed;
        _user.originationFee = _user.originationFee + _fee;
        _user.lastUpdatedTimestamp = block.timestamp;
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
                _pool.users[_user]
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
            _newRateMode == LibFacet.InterestRateMode.VARIABLE
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
            _pool.variableBorrowLiquidity >= _amount,
            "The amount that is being subtracted from the variable borrows is incorrect."
        );
        _pool.variableBorrowLiquidity -= _amount;
    }

    function increaseTotalVariableBorrows(
        LibFacet.Pool storage _pool,
        uint256 _amount
    ) internal {
        _pool.variableBorrowLiquidity += _amount;
    }

    function getPoolLiquidityRate(address _pool) public view returns (uint256) {
        return LibFacet.lpcStorage().pools[_pool].rates.currentLiquidityRate;
    }

    function getUserCurrentBorrowRateMode(LibFacet.UserPoolData memory _user)
        internal
        pure
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
        if (_pool.borrowedLiquidity > 0) {
            _pool.cumulatedLiquidityIndex = calculateLinearInterest(
                _pool.rates.currentLiquidityRate,
                _pool.lastUpdatedTimestamp
            ).rayMul(_pool.cumulatedLiquidityIndex);
            _pool.cumulatedVariableBorrowIndex = calculateCompoundedInterest(
                _pool.rates.variableBorrowRate,
                LibFacet.SECONDS_IN_A_YEAR,
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
            _pool.providedLiquidity + _liquidityAdded - _liquidityTaken,
            _pool.variableBorrowLiquidity,
            _pool.rates.interestRateSlopeBelow,
            _pool.rates.interestRateSlopeAbove,
            _pool.rates.baseVariableBorrowRate,
            _pool.rates.targetUtilisationRate
        );
        _pool.rates.overallBorrowRate = _pool.rates.variableBorrowRate;
        _pool.lastUpdatedTimestamp = block.timestamp;
    }

    function calculateInterestRates(
        uint256 _totalLiquidity,
        uint256 _totalVariableBorrows,
        uint256 _variableRateSlope1,
        uint256 _variableRateSlope2,
        uint256 _baseVariableBorrowRate,
        uint256 _optimalUtilizationRate
    )
        public
        pure
        returns (
            uint256 currentVariableBorrowRate,
            uint256 currentLiquidityRate
        )
    {
        uint256 totalBorrows = _totalVariableBorrows; /// @dev + totalStableBorrows
        uint256 utilizationRate = (_totalLiquidity == 0 && totalBorrows == 0)
            ? 0
            : totalBorrows.rayDiv(_totalLiquidity + totalBorrows);

        if (utilizationRate > _optimalUtilizationRate) {
            uint256 excessUtilizationRateRatio = (utilizationRate -
                _optimalUtilizationRate).rayDiv(
                    WadRayMath.RAY - _optimalUtilizationRate
                );
            currentVariableBorrowRate =
                _baseVariableBorrowRate +
                _variableRateSlope1 +
                (_variableRateSlope2.rayMul(excessUtilizationRateRatio));
        } else {
            currentVariableBorrowRate =
                _baseVariableBorrowRate +
                (
                    utilizationRate.rayDiv(_optimalUtilizationRate).rayMul(
                        _variableRateSlope1
                    )
                );
        }
        uint256 overallBorrowRate = calculateOverallBorrowRate(
            _totalVariableBorrows,
            currentVariableBorrowRate
        );
        currentLiquidityRate = overallBorrowRate.rayMul(utilizationRate);
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

    function getPoolLiquidationBonus(address _pool)
        public
        view
        returns (uint256)
    {
        return LibFacet.lpcStorage().pools[_pool].liquidationBonus;
    }

    function getUserBorrowBalances(address _pool, address _user)
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        LibFacet.UserPoolData storage user = pool.users[_user];
        if (user.principalBorrowBalance == 0) return (0, 0, 0);

        uint256 compoundedBalance = getCompoundedBorrowBalance(user, pool);
        return (
            user.principalBorrowBalance,
            compoundedBalance,
            compoundedBalance - user.principalBorrowBalance
        );
    }

    function getUserOriginationFee(address _pool, address _user)
        public
        view
        returns (uint256)
    {
        return LibFacet.lpcStorage().pools[_pool].users[_user].originationFee;
    }

    function calculateCompoundedInterest(
        uint256 _variableBorrowRate,
        uint256 _secondsInAYear,
        uint256 _timestamp,
        uint256 _lastUpdatedTimestamp
    ) public pure returns (uint256) {
        uint256 ratePerSecond = _variableBorrowRate / _secondsInAYear;
        return
            (WadRayMath.RAY + ratePerSecond).rayPow(
                _timestamp - _lastUpdatedTimestamp
            );
    }

    /// @dev calculates interest using linear interest rate formula
    function calculateLinearInterest(
        uint256 _currentLiquidityRate,
        uint256 _lastUpdatedTimestamp
    ) internal view returns (uint256) {
        uint256 timeDelta = calculateTimeDelta(
            block.timestamp,
            _lastUpdatedTimestamp,
            LibFacet.SECONDS_IN_A_YEAR
        );
        return _currentLiquidityRate.rayMul(timeDelta) + WadRayMath.RAY;
    }

    function calculateTimeDelta(
        uint256 _timestamp,
        uint256 _lastUpdatedTimestamp,
        uint256 _secondsInAYear
    ) internal pure returns (uint256) {
        return (_timestamp - _lastUpdatedTimestamp) / _secondsInAYear;
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
            cumulatedInterest = calculateCompoundedInterest(
                _pool.rates.variableBorrowRate,
                LibFacet.SECONDS_IN_A_YEAR,
                block.timestamp,
                _pool.lastUpdatedTimestamp
            ).rayMul(_pool.cumulatedVariableBorrowIndex).rayDiv(
                    _user.cumulatedVariableBorrowIndex
                );
        }

        compoundedBalance = principalBorrowBalance
            .rayMul(cumulatedInterest)
            .rayToWad();

        return compoundedBalance;
    }

    function getUserVariableBorrowIndex(address _pool, address _user)
        public
        view
        returns (uint256)
    {
        return
            LibFacet
                .lpcStorage()
                .pools[_pool]
                .users[_user]
                .rates
                .variableBorrowRate;
    }

    function getUserUsePoolAsCollateral(address _pool, address _user)
        public
        view
        returns (bool)
    {
        return LibFacet.lpcStorage().pools[_pool].users[_user].useAsCollateral;
    }

    function getUserCurrentBorrowRate(
        LibFacet.Pool storage _pool,
        address _user
    ) internal view returns (uint256) {
        LibFacet.InterestRateMode rateMode = getUserCurrentBorrowRateMode(
            _pool.users[_user]
        );

        if (rateMode == LibFacet.InterestRateMode.NONE) return 0;

        return
            rateMode == LibFacet.InterestRateMode.STABLE
                ? 0
                : _pool.rates.variableBorrowRate;
    }

    function getUserCurrentBorrowRateMode(address _pool, address _user)
        public
        view
        returns (LibFacet.InterestRateMode)
    {
        return LibFacet.lpcStorage().pools[_pool].users[_user].rates.rateMode;
    }

    function getUserLastUpdatedTimestamp(address _pool, address _user)
        public
        view
        returns (uint256)
    {
        return
            LibFacet
                .lpcStorage()
                .pools[_pool]
                .users[_user]
                .lastUpdatedTimestamp;
    }

    function getUserBasicPoolData(address _pool, address _user)
        public
        view
        returns (
            uint256 compoundedLiquidityBalance,
            uint256 compoundedBorrowBalance,
            uint256 originationFee,
            bool userUsesPoolAsCollateral
        )
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        /// Q: How to compound the deposited balance? Don't return just the 'principal' amount.
        /// A: Store the compounded interest from loans and distribute it amongst the depositors based on their share.
        uint256 assetBalance = pool.users[_user].liquidityProvided;
        if (pool.users[_user].principalBorrowBalance == 0)
            return (assetBalance, 0, 0, pool.users[_user].useAsCollateral);

        return (
            assetBalance,
            getCompoundedBorrowBalance(pool.users[_user], pool),
            pool.users[_user].originationFee,
            pool.users[_user].useAsCollateral
        );
    }

    function getUserCumulatedRewards(
        address _pool,
        address _user,
        uint256 _totalRewards
    ) public view returns (uint256) {
        uint256 userShare = DataProvider(address(this)).getUserRewardShare(
            _pool,
            _user
        );

        return (_totalRewards * userShare) / 10**18;
    }

    function getPoolDepositInformation(address _pool, address _user)
        public
        view
        returns (
            string memory asset,
            uint256 depositedLiquidity,
            uint256 userDepositedLiquidity,
            uint256 borrowedLiquidity,
            uint256 loanToValue,
            bool isUsableAsCollateral
        )
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        return (
            pool.asset,
            pool.providedLiquidity,
            pool.users[_user].liquidityProvided,
            pool.borrowedLiquidity,
            pool.loanToValue,
            pool.isUsableAsCollateral
        );
    }

    function getPoolDisplayInformation(address _pool, address _user)
        public
        view
        returns (LibFacet.getPoolDisplayDataLocalVars memory)
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        return
            LibFacet.getPoolDisplayDataLocalVars(
                pool.asset,
                pool.loanToValue,
                pool.liquidationThreshold,
                pool.liquidationBonus,
                pool.providedLiquidity,
                pool.borrowedLiquidity,
                pool.users[_user].principalBorrowBalance,
                DataProvider(address(this)).calculateUserAmountToRepay(
                    _pool,
                    _user
                ),
                pool.isBorrowingEnabled,
                pool.isUsableAsCollateral
            );
    }

    function getPoolConfiguration(address _pool)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
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

    function getPoolDecimals(address _pool) public view returns (uint256) {
        return LibFacet.lpcStorage().pools[_pool].decimals;
    }

    function getUserMaxRedeemAmount(address _pool, address _user)
        public
        view
        returns (uint256)
    {
        return
            getUserCumulatedRewards(
                _pool,
                _user,
                LibFacet.lpcStorage().pools[_pool].rewardsLiquidity
            ) +
            LibFacet.lpcStorage().pools[_pool].users[_user].liquidityProvided;
    }

    function getUserCollateralBalance(address _pool, address _user)
        public
        view
        returns (uint256)
    {
        return
            LibFacet.lpcStorage().pools[_pool].users[_user].useAsCollateral
                ? LibFacet
                    .lpcStorage()
                    .pools[_pool]
                    .users[_user]
                    .liquidityProvided
                : 0;
    }

    function getPoolCumulatedRewards(address _pool)
        public
        view
        returns (uint256)
    {
        return LibFacet.lpcStorage().pools[_pool].rewardsLiquidity;
    }

    function getPoolAvailableLiquidity(address _pool)
        public
        view
        returns (uint256)
    {
        return
            LibFacet.lpcStorage().pools[_pool].providedLiquidity +
            LibFacet.lpcStorage().pools[_pool].rewardsLiquidity -
            LibFacet.lpcStorage().pools[_pool].borrowedLiquidity;
    }

    function calculateUserDepositAPY(address _pool)
        public
        view
        returns (uint256)
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        if (pool.providedLiquidity == 0) return 0;

        uint256 oneYearAhead = pool.lastUpdatedTimestamp + 365 days;
        uint256 cumulatedInterest = LendingPoolCore(address(this))
            .calculateCompoundedInterest(
                pool.rates.variableBorrowRate,
                LibFacet.SECONDS_IN_A_YEAR,
                oneYearAhead,
                pool.lastUpdatedTimestamp
            )
            .rayMul(pool.cumulatedVariableBorrowIndex);
        uint256 compoundedInterest = pool
            .borrowedLiquidity
            .wadToRay()
            .rayMul(cumulatedInterest)
            .rayToWad();
        uint256 cumulatedValue = compoundedInterest - pool.borrowedLiquidity;

        return
            (pool.providedLiquidity + cumulatedValue).wadDiv(
                pool.providedLiquidity
            ) - WadRayMath.WAD;
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

    function setUserUsePoolAsCollateralInternal(
        address _pool,
        address _user,
        bool _useAsCollateral
    ) public {
        LibFacet
            .lpcStorage()
            .pools[_pool]
            .users[_user]
            .useAsCollateral = _useAsCollateral;
    }

    function initializeUserData(LibFacet.UserPoolData storage _user) internal {
        _user.cumulatedVariableBorrowIndex = WadRayMath.RAY;
        _user.cumulatedVariableBorrowIndex = WadRayMath.RAY;
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
            bool success = ERC20(_pool).transferFrom(_user, _pool, _amount);
            require(success, "Error while sending ERC20 tokens to pool.");
        }
    }

    function transferToUser(
        address _pool,
        address _user,
        uint256 _amount
    ) public {
        if (_pool == LibFacet.facetStorage().ethAddress) {
            EthMock(payable(_pool)).transferEthToUser(_user, _amount);
        } else {
            UsdcMock(_pool).customApprove(
                _pool,
                LibFacet.facetStorage().diamondAddress,
                _amount
            );
            bool success = ERC20(_pool).transferFrom(_pool, _user, _amount);
            require(success, "Error on sending ERC20 to user.");
        }
    }

    function transferToFeeCollector(
        address _token,
        address _user,
        uint256 _amount
    ) public payable {
        address feeProvider = LibFacet.facetStorage().feeProviderAddress;
        if (_token != LibFacet.facetStorage().ethAddress) {
            bool success = ERC20(_token).transferFrom(
                _user,
                feeProvider,
                _amount
            );
            require(success, "Error on sending ERC20 tokens to fee collector.");
        } else {
            (bool result, ) = feeProvider.call{value: _amount}("");
            require(result, "Transfer of ETH failed");
        }
    }
}
