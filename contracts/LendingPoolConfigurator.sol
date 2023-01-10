// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./libraries/LibFacet.sol";
import "./libraries/WadRayMath.sol";
import "hardhat/console.sol";

contract LendingPoolConfigurator {
    using WadRayMath for uint256;

    function init(
        address _ethAddress,
        address _lpcAddress,
        address _dfAddress
    ) public {
        LibFacet.facetStorage().ethAddress = _ethAddress;
        LibFacet.facetStorage().lpcAddress = _lpcAddress;
        LibFacet.facetStorage().dataFeedAddress = _dfAddress;
        LibFacet.lpcStorage().SECONDS_IN_YEAR = 31556926;
    }

    function initPool(address _pool, LibFacet.TokenVolatility _volatility)
        public
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        pool.cumulatedLiquidityIndex = WadRayMath.RAY;
        pool.cumulatedVariableBorrowIndex = WadRayMath.RAY;
        pool.isActive = true;
        pool.lastUpdatedTimestamp = block.timestamp;
        if (_volatility == LibFacet.TokenVolatility.LOW) {
            pool.rates.interestRateSlopeAbove = 110 * WadRayMath.RAY;
            pool.rates.interestRateSlopeBelow = 5 * WadRayMath.RAY;
            pool.rates.baseVariableBorrowRate = 1 * WadRayMath.RAY;
            pool.rates.targetUtilisationRate = 85;
            pool.liquidationThreshold = 90; /// TODO: consider if this is a good default value
            pool.loanToValue = 85;
        } else if (_volatility == LibFacet.TokenVolatility.HIGH) {
            pool.rates.interestRateSlopeAbove = 250 * WadRayMath.RAY;
            pool.rates.interestRateSlopeBelow = 8 * WadRayMath.RAY;
            pool.rates.baseVariableBorrowRate = 0 * WadRayMath.RAY;
            pool.rates.targetUtilisationRate = 70;
            pool.liquidationThreshold = 70;
            pool.loanToValue = 65;
        }
    }
}
