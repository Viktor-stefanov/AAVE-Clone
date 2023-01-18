// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "../libraries/LibFacet.sol";
import "../libraries/WadRayMath.sol";
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
    }

    function initPool(
        address _pool,
        string memory _asset,
        uint256 _decimals,
        LibFacet.TokenVolatility _volatility
    ) external {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        pool.asset = _asset;
        pool.decimals = _decimals;
        pool.cumulatedLiquidityIndex = WadRayMath.RAY;
        pool.cumulatedVariableBorrowIndex = WadRayMath.RAY;
        pool.isActive = true;
        pool.isBorrowingEnabled = true;
        pool.isUsableAsCollateral = true;
        pool.lastUpdatedTimestamp = block.timestamp;
        if (_volatility == LibFacet.TokenVolatility.LOW) {
            pool.rates.interestRateSlopeAbove = 60 * WadRayMath.RAY;
            pool.rates.interestRateSlopeBelow = 4 * WadRayMath.RAY;
            pool.rates.baseVariableBorrowRate = 0 * WadRayMath.RAY;
            pool.rates.targetUtilisationRate = (90 * WadRayMath.RAY) / 100; // * 0.9
            pool.liquidationThreshold = 90; /// TODO: consider if this is a good default value
            pool.liquidationBonus = 10;
            pool.loanToValue = 85;
            pool.baseLTV = 85;
        } else if (_volatility == LibFacet.TokenVolatility.HIGH) {
            pool.rates.interestRateSlopeAbove = (100 * WadRayMath.RAY); // / 100;
            pool.rates.interestRateSlopeBelow = (8 * WadRayMath.RAY); // / 100;
            pool.rates.baseVariableBorrowRate = 0;
            pool.rates.targetUtilisationRate = (65 * WadRayMath.RAY); // / 100;
            pool.liquidationThreshold = 70;
            pool.liquidationBonus = 5;
            pool.loanToValue = 65;
            pool.baseLTV = 65;
        }
        LibFacet.lpcStorage().allPools.push(_pool);
    }
}
