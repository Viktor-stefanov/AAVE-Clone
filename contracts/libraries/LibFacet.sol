// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

library LibFacet {
    bytes32 constant LENDING_POOL_CORE_STORAGE_POSITION =
        keccak256("diamonds.standart.lending.pool.core.storage");
    bytes32 constant FACET_STORAGE_POSITION =
        keccak256("diamonds.standart.facet.storage");

    // user data tied to his deposit
    struct UserPoolData {
        uint256 liquidityProvided;
        uint256 principalBorrowBalance;
        uint256 cumulatedVariableBorrowIndex; // interest cumulated by the variable borrows of the specific user
        uint256 compoundedBorrowBalance; // princialBorrowBalance + cumulatedVariableBorrowIndex
        uint256 collateralEthBalance;
        uint256 liquidationThreshold;
        uint256 originationFee;
        uint256 healthFactor;
    }

    struct Pool {
        uint256 totalLiquidity;
        uint256 totalBorrowedLiquidity;
        uint256 totalVariableBorrowLiquidity;
        uint256 depositApy; // utilisation rate * (share of variable borrows * variable rate)
        uint256 cumulatedLiquidityIndex; // interest cumulated by the reserve during the time interval Dt
        uint256 reserveNormalizedIncome; // Ongoing interest cumulated by the reserve
        uint256 cumulatedVariableBorrowIndex;
        uint256 loanToValue; // weighted average of the LTVs of the currencies making up the reserve
        uint256 liquidationThreshold;
        uint256 liquidationBonus; // represented in percentage
        uint256 lastUpdatedTimestamp;
        bool isBorrowingEnabled;
        bool isUsableAsCollateral;
        bool isActive;
        bool isFreezed; // only allow repays and redeems, but not deposits, new borrowings or rate swap.
        InterestRate rates;
        mapping(address => UserPoolData) user;
        address[] users;
    }

    struct LPCStorage {
        mapping(address => Pool) pools;
        address[] allPools;
        uint256 SECONDS_IN_YEAR;
    }

    struct FacetStorage {
        address ethAddress;
        address lpcAddress;
    }

    struct InterestRate {
        uint256 utilisationRate;
        uint256 targetUtilisationRate;
        uint256 interestRateSlopeBelow; // constant representing the scaling of the interest rate vs the utilization.
        uint256 interestRateSlopeAbove;
        uint256 baseVariableBorrowRate; // constant for totalBorrows = 0. Expressed in ray
        uint256 variableBorrowRate;
        uint256 overallBorrowRate; // (VariableBorrowRate * TotalVariableBorrows) / totalBorrows
        uint256 currentLiquidityRate; // overallBorrowRate * utilizationRate
    }

    enum TokenVolatility {
        low,
        high
    }

    struct InterestRateStorage {
        TokenVolatility volatility;
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
}
