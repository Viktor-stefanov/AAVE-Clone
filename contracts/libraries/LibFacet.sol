// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "../lendingpool/LendingPoolCore.sol";
import "../lendingpool/DataProvider.sol";
import "../lendingpool/FeeProvider.sol";
import "../mocks/PriceFeed.sol";
import "hardhat/console.sol";

library LibFacet {
    uint256 internal constant SECONDS_IN_A_YEAR = 365 days;
    bytes32 internal constant LENDING_POOL_CORE_STORAGE_POSITION =
        keccak256("diamonds.standart.lending.pool.core.storage");
    bytes32 internal constant FACET_STORAGE_POSITION =
        keccak256("diamonds.standart.facet.storage");

    // user data tied to a specific pool
    struct UserPoolData {
        uint256 liquidityProvided;
        uint256 principalBorrowBalance;
        uint256 cumulatedVariableBorrowIndex;
        uint256 lastCumulatedVariableBorrowIndex;
        uint256 compoundedBorrowBalance;
        uint256 collateralETHBalance;
        uint256 liquidationThreshold;
        uint256 originationFee;
        uint256 healthFactor;
        uint256 lastUpdatedTimestamp;
        bool useAsCollateral;
        UserInterestRate rates;
    }

    struct Pool {
        string asset;
        uint256 decimals;
        uint256 providedLiquidity;
        uint256 borrowedLiquidity;
        uint256 rewardsLiquidity;
        uint256 variableBorrowLiquidity;
        uint256 cumulatedLiquidityIndex; // interest cumulated by the reserve during the time interval Dt
        uint256 reserveNormalizedIncome; // Ongoing interest cumulated by the reserve
        uint256 cumulatedVariableBorrowIndex;
        uint256 baseLTV;
        uint256 loanToValue;
        uint256 liquidationThreshold;
        uint256 liquidationBonus; // represented in percentage
        uint256 lastUpdatedTimestamp;
        bool isBorrowingEnabled;
        bool isUsableAsCollateral;
        bool isActive;
        bool isFreezed; // only allow repays and redeems, but not deposits, new borrowings or rate swap.
        InterestRate rates;
        address[] allUsers;
        mapping(address => UserPoolData) users;
    }

    struct LPCStorage {
        mapping(address => Pool) pools;
        address[] allPools;
    }

    struct FacetStorage {
        address ethAddress;
        address lpcAddress;
        address dataProviderAddress;
        address priceFeedAddress;
        address feeProviderAddress;
    }

    struct InterestRate {
        InterestRateMode rateMode;
        uint256 targetUtilisationRate;
        uint256 interestRateSlopeBelow; // constant representing the scaling of the interest rate vs the utilization.
        uint256 interestRateSlopeAbove;
        uint256 baseVariableBorrowRate; // constant for totalBorrows = 0. Expressed in ray
        uint256 variableBorrowRate;
        uint256 overallBorrowRate; // (VariableBorrowRate * TotalVariableBorrows) / totalBorrows
        uint256 currentLiquidityRate; // overallBorrowRate * utilizationRate
    }

    struct UserInterestRate {
        InterestRateMode rateMode;
        uint256 variableBorrowRate;
        uint256 stableBorrowRate;
        uint256 cumulatedVariableBorrowIndex;
    }

    enum TokenVolatility {
        LOW,
        HIGH
    }

    enum InterestRateMode {
        VARIABLE,
        STABLE,
        NONE
    }

    function lpcStorage() internal pure returns (LPCStorage storage lpcs) {
        bytes32 position = LENDING_POOL_CORE_STORAGE_POSITION;
        assembly {
            lpcs.slot := position
        }
    }

    function facetStorage() internal pure returns (FacetStorage storage fs) {
        bytes32 position = FACET_STORAGE_POSITION;
        assembly {
            fs.slot := position
        }
    }

    function getDataProvider() internal view returns (DataProvider) {
        return DataProvider(facetStorage().dataProviderAddress);
    }

    function getFeeProvider() internal view returns (FeeProvider) {
        return FeeProvider(facetStorage().feeProviderAddress);
    }

    function getPriceFeed() internal view returns (PriceFeed) {
        return PriceFeed(facetStorage().priceFeedAddress);
    }
}
