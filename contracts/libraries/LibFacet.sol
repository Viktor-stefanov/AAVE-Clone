// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

library LibFacet {
    // each user has specific data tied to his deposit
    struct UserPoolData {
        uint256 principalBorrowBalance;
        uint256 cummulatedBorrowIndex;
        uint256 originationFee;
        uint40 lastUpdatedTimestamp;
        bool useAsCollateral;
    }

    struct Pool {
        uint256 totalLiquidity;
        uint256 totalBorrows;
        uint256 utilizationRate; // totalBorrows / totalLiquidity
        uint256 targetUtilizationRate;
        uint256 baseVariableBorrowRate; // constant for totalBorrows = 0. Expressed in ray
        uint256 interestRateSlopeBelow; // constant representing the scaling of the interest rate vs the utilization.
        uint256 interestRateSlopeAbove;
        uint256 variableBorrowRate;
        uint256 overallBorrowRate; // (VariableBorrowRate * TotalVariableBorrows) / totalBorrows
        uint256 currentLiquidityRate; // overallBorrowRate * utilizationRate
        uint256 cumulatedLiquidityIndex; // interest cumulated by the reserve during the time interval Dt
        uint256 baseLoanToValue; // weighted average of the LTVs of the currencies making up the reserve
        uint256 liquidationThreshold;
        uint256 liquidationBonus; // represented in percentage
        uint40 lastUpdateTimestamp;
        address interestRateStrategyAddress;
        bool borrowingEnabled;
        bool isUsableAsCollateral;
        bool isActive;
        bool isFreezed; // only allow repays and redeems, but not deposits, new borrowings or rate swap.
    }

    struct LendingPoolCoreStorage {
        uint256 SECONDS_IN_YEAR;
        mapping(string => Pool) pools;
    }
}
