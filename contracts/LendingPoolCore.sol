// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/LibFacet.sol";
import "./libraries/WadRayMath.sol";

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

    function updatePoolOnDeposit(address _pool, uint256 _amount) internal {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        updateCumulativeIndexes(pool);
        pool.totalLiquidity += _amount;
        updatePoolInterestRates(pool);
        pool.user[msg.sender].liquidityProvided += _amount;
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

    function updatePoolInterestRates(LibFacet.Pool storage _pool) internal {
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
