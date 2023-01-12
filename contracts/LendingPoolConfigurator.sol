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
        address _pfAddress,
        address _dpAddress
    ) external {
        console.log("initialized global state");
        LibFacet.facetStorage().ethAddress = _ethAddress;
        LibFacet.facetStorage().priceFeedAddress = _pfAddress;
        LibFacet.facetStorage().dataProviderAddress = _dpAddress;
        LibFacet.facetStorage().lpcAddress = _lpcAddress;
        LibFacet.lpcStorage().SECONDS_IN_YEAR = 31556926;
        LibFacet.lpcStorage().allPools = new address[](10);
    }

    function initPool(
        address _pool,
        uint256 _decimals,
        LibFacet.TokenVolatility _volatility
    ) external {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        pool.asset = _pool;
        pool.decimals = _decimals;
        pool.cumulatedLiquidityIndex = WadRayMath.RAY;
        pool.cumulatedVariableBorrowIndex = WadRayMath.RAY;
        pool.isActive = true;
        pool.isBorrowingEnabled = true;
        pool.isUsableAsCollateral = true;
        pool.lastUpdatedTimestamp = block.timestamp;
        if (_volatility == LibFacet.TokenVolatility.LOW) {
            pool.rates.interestRateSlopeAbove = 110 * WadRayMath.RAY;
            pool.rates.interestRateSlopeBelow = 5 * WadRayMath.RAY;
            pool.rates.baseVariableBorrowRate = 1 * WadRayMath.RAY;
            pool.rates.targetUtilisationRate = 85 * WadRayMath.RAY;
            pool.liquidationThreshold = 90; /// TODO: consider if this is a good default value
            pool.loanToValue = 85;
            pool.baseLTV = 85;
        } else if (_volatility == LibFacet.TokenVolatility.HIGH) {
            pool.rates.interestRateSlopeAbove = 250 * WadRayMath.RAY;
            pool.rates.interestRateSlopeBelow = 8 * WadRayMath.RAY;
            pool.rates.baseVariableBorrowRate = 0;
            pool.rates.targetUtilisationRate = 70 * WadRayMath.RAY;
            pool.liquidationThreshold = 70;
            pool.loanToValue = 65;
            pool.baseLTV = 65;
        }
        LibFacet.lpcStorage().allPools[0] = _pool;
        console.log("initialized pool state");
        console.log(LibFacet.lpcStorage().allPools[0]);
    }
}
