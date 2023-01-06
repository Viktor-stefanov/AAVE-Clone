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
<<<<<<< HEAD
        updatePoolIndexes(pool);
=======
        updateCumulativeIndexes(pool);
>>>>>>> 8368816306b1009bc08570c56343b91039488f15
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
        updatePoolRates(pool);
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
<<<<<<< HEAD
        updatePoolIndexes(pool);
=======
        updateCumulativeIndexes(pool);
>>>>>>> 8368816306b1009bc08570c56343b91039488f15
        pool.totalLiquidity += _amount;
        updatePoolRates(pool);
        pool.lastUpdatedTimestamp = block.timestamp;
        pool.user[msg.sender].liquidityProvided += _amount;
    }

<<<<<<< HEAD
    function updatePoolIndexes(LibFacet.Pool storage _pool) internal {
        uint256 yearlyPeriod = getYearlyPeriod(
            block.timestamp,
            _pool.lastUpdatedTimestamp,
            LibFacet.lpcStorage().SECONDS_IN_YEAR
        );
        _pool.reserveNormalizedIncome = WadRayMath.rayMul(
            WadRayMath.rayMul(_pool.rates.currentLiquidityRate, yearlyPeriod) +
                1,
            _pool.cumulatedLiquidityIndex
        );
        _pool.cumulatedLiquidityIndex = WadRayMath.rayMul(
            WadRayMath.rayMul(_pool.rates.currentLiquidityRate, yearlyPeriod) +
                1,
            _pool.cumulatedLiquidityIndex
        );
        _pool.cumulatedVariableBorrowIndex = WadRayMath.rayMul(
            (1 +
                WadRayMath.rayDiv(
                    _pool.rates.variableBorrowRate,
                    LibFacet.lpcStorage().SECONDS_IN_YEAR
                ))**(block.timestamp - _pool.lastUpdatedTimestamp),
            _pool.cumulatedVariableBorrowIndex
        );
        for (uint256 i = 0; i < _pool.users.length; i++) {
            _pool.user[_pool.users[i]].compoundedBorrowBalance = WadRayMath
                .rayMul(
                    (
                        WadRayMath.rayMul(
                            WadRayMath.rayDiv(
                                _pool.cumulatedVariableBorrowIndex,
                                _pool
                                    .user[_pool.users[i]]
                                    .cumulatedVariableBorrowIndex
                            ),
                            (1 +
                                WadRayMath.rayDiv(
                                    _pool.rates.variableBorrowRate,
                                    LibFacet.lpcStorage().SECONDS_IN_YEAR
                                ))
                        )
                    )**(block.timestamp - _pool.lastUpdatedTimestamp),
                    _pool.user[_pool.users[i]].principalBorrowBalance
                );
            _pool.user[_pool.users[i]].cumulatedVariableBorrowIndex = WadRayMath
                .rayMul(
                    (1 +
                        WadRayMath.rayDiv(
                            _pool.rates.variableBorrowRate,
                            LibFacet.lpcStorage().SECONDS_IN_YEAR
                        ))**(block.timestamp - _pool.lastUpdatedTimestamp),
                    _pool.user[_pool.users[i]].cumulatedVariableBorrowIndex
                );
            _pool.user[_pool.users[i]].healthFactor = getHealthFactor(
                _pool.user[_pool.users[i]].collateralEthBalance,
                _pool.user[_pool.users[i]].liquidationThreshold,
                _pool.user[_pool.users[i]].compoundedBorrowBalance
            );
        }
    }

    function updatePoolRates(LibFacet.Pool storage _pool) internal {
=======
    function updateCumulativeIndexes(LibFacet.Pool storage _pool) internal {
        // do all this only if totalBorrows > 0
        _pool.cumulatedLiquidityIndex = calculateCumulatedLiquidityInterest(
            _pool.rates.currentLiquidityRate,
            _pool.lastUpdatedTimestamp
        ).rayMul(_pool.cumulatedLiquidityIndex);
        _pool
            .cumulatedVariableBorrowIndex = calculateCumulatedVariableBorrowInterest(
            _pool.rates.variableBorrowRate,
            LibFacet.lpcStorage().SECONDS_IN_YEAR,
            block.timestamp,
            _pool.lastUpdatedTimestamp
        ).rayMul(_pool.cumulatedVariableBorrowIndex);

        //_pool.reserveNormalizedIncome = WadRayMath.rayMul(
        //    WadRayMath.rayMul(_pool.rates.currentLiquidityRate, yearlyPeriod) +
        //        1,
        //    _pool.cumulatedLiquidityIndex
        //);
        //for (uint256 i = 0; i < _pool.users.length; i++) {
        //    _pool.user[_pool.users[i]].compoundedBorrowBalance = WadRayMath
        //        .rayMul(
        //            (
        //                WadRayMath.rayMul(
        //                    WadRayMath.rayDiv(
        //                        _pool.cumulatedVariableBorrowIndex,
        //                        _pool
        //                            .user[_pool.users[i]]
        //                            .cumulatedVariableBorrowIndex
        //                    ),
        //                    (1 +
        //                        WadRayMath.rayDiv(
        //                            _pool.rates.variableBorrowRate,
        //                            LibFacet.lpcStorage().SECONDS_IN_YEAR
        //                        ))
        //                )
        //            )**(block.timestamp - _pool.lastUpdatedTimestamp),
        //            _pool.user[_pool.users[i]].principalBorrowBalance
        //        );
        //    _pool.user[_pool.users[i]].cumulatedVariableBorrowIndex = WadRayMath
        //        .rayMul(
        //            (1 +
        //                WadRayMath.rayDiv(
        //                    _pool.rates.variableBorrowRate,
        //                    LibFacet.lpcStorage().SECONDS_IN_YEAR
        //                ))**(block.timestamp - _pool.lastUpdatedTimestamp),
        //            _pool.user[_pool.users[i]].cumulatedVariableBorrowIndex
        //        );
        //    _pool.user[_pool.users[i]].healthFactor = getHealthFactor(
        //        _pool.user[_pool.users[i]].collateralEthBalance,
        //        _pool.user[_pool.users[i]].liquidationThreshold,
        //        _pool.user[_pool.users[i]].compoundedBorrowBalance
        //    );
        //}
    }

    function updatePoolInterestRates(LibFacet.Pool storage _pool) internal {
>>>>>>> 8368816306b1009bc08570c56343b91039488f15
        _pool.rates.utilisationRate =
            _pool.totalBorrowedLiquidity /
            _pool.totalLiquidity;
        _pool.rates.variableBorrowRate = _pool.rates.utilisationRate <=
            _pool.rates.targetUtilisationRate
            ? _pool.rates.baseVariableBorrowRate +
                WadRayMath.rayMul(
                    (_pool.rates.utilisationRate /
                        _pool.rates.targetUtilisationRate),
                    _pool.rates.interestRateSlopeBelow
                )
            : _pool.rates.baseVariableBorrowRate +
                _pool.rates.interestRateSlopeBelow +
                WadRayMath.rayMul(
                    ((_pool.rates.utilisationRate -
                        _pool.rates.targetUtilisationRate) /
                        (1 - _pool.rates.targetUtilisationRate)),
                    _pool.rates.interestRateSlopeAbove
                );
        _pool.rates.overallBorrowRate = _pool.totalBorrowedLiquidity == 0
            ? 0
            : WadRayMath.rayDiv(
                WadRayMath.rayMul(
                    _pool.rates.variableBorrowRate,
                    _pool.totalVariableBorrowLiquidity
                ),
                _pool.totalBorrowedLiquidity
            );
        _pool.rates.currentLiquidityRate = WadRayMath.rayMul(
            _pool.rates.overallBorrowRate,
            _pool.rates.utilisationRate
        );
<<<<<<< HEAD
    }

    function test(address _pool) external view returns (uint256) {
        return LibFacet.lpcStorage().pools[_pool].totalLiquidity;
=======
        _pool.lastUpdatedTimestamp = block.timestamp;
    }

    function calculateCumulatedVariableBorrowInterest(
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

    function calculateCumulatedLiquidityInterest(
        uint256 _currentLiquidityRate,
        uint256 _lastUpdatedTimestamp
    ) internal view returns (uint256) {
        uint256 yearlyPeriod = getYearlyPeriod(
            block.timestamp,
            _lastUpdatedTimestamp,
            LibFacet.lpcStorage().SECONDS_IN_YEAR
        );
        return _currentLiquidityRate.rayMul(yearlyPeriod) + WadRayMath.RAY;
>>>>>>> 8368816306b1009bc08570c56343b91039488f15
    }

    function getYearlyPeriod(
        uint256 _timestamp,
        uint256 _lastUpdatedTimestamp,
        uint256 _secondsInAYear
    ) internal pure returns (uint256) {
        return
<<<<<<< HEAD
            WadRayMath.wadDiv(
                WadRayMath.WAD * (_timestamp - _lastUpdatedTimestamp),
                _secondsInAYear
=======
            (_timestamp - _lastUpdatedTimestamp).wadToRay().rayDiv(
                _secondsInAYear.wadToRay()
>>>>>>> 8368816306b1009bc08570c56343b91039488f15
            );
    }

    function getHealthFactor(
        uint256 _collateralEth,
        uint256 _liquidationThreshold,
        uint256 _compoundedBorrowBalance
    ) internal pure returns (uint256) {
        return
<<<<<<< HEAD
            WadRayMath.rayDiv(
                WadRayMath.rayMul(_collateralEth, _liquidationThreshold),
=======
            _collateralEth.rayMul(_liquidationThreshold).rayDiv(
>>>>>>> 8368816306b1009bc08570c56343b91039488f15
                _compoundedBorrowBalance
            );
    }
}
