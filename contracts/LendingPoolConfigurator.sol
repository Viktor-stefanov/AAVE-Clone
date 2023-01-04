// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./libraries/LibFacet.sol";
import "./libraries/WadRayMath.sol";
import "./LendingPoolCore.sol";

contract LendingPoolConfigurator {
    using WadRayMath for uint256;

    function init() external {}

    function createPool(
        address _pool,
        uint256 _amount,
        LibFacet.TokenVolatility _volatility
    ) external payable {
        initPool(_pool, _volatility);
        LendingPoolCore(LibFacet.facetStorage().lpcAddress).deposit(
            _pool,
            msg.sender,
            _amount
        );
    }

    function initPool(address _pool, LibFacet.TokenVolatility _volatility)
        internal
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        pool.cumulatedLiquidityIndex = WadRayMath.RAY;
        pool.cumulatedVariableBorrowIndex = WadRayMath.RAY;
        pool.isActive = true;
        pool.lastUpdatedTimestamp = block.timestamp;
        if (_volatility == LibFacet.TokenVolatility.low) {
            pool.rates.interestRateSlopeAbove = 110 * WadRayMath.RAY;
            pool.rates.interestRateSlopeBelow = 5 * WadRayMath.RAY;
            pool.rates.baseVariableBorrowRate = 1 * WadRayMath.RAY;
            pool.rates.targetUtilisationRate = 85;
            pool.liquidationThreshold = 90; /// TODO: consider if this is a good default value
            pool.loanToValue = 85;
        } else if (_volatility == LibFacet.TokenVolatility.high) {
            pool.rates.interestRateSlopeAbove = 250 * WadRayMath.RAY;
            pool.rates.interestRateSlopeBelow = 8 * WadRayMath.RAY;
            pool.rates.baseVariableBorrowRate = 0 * WadRayMath.RAY;
            pool.rates.targetUtilisationRate = 70;
            pool.liquidationThreshold = 70;
            pool.loanToValue = 65;
        }
    }
}
