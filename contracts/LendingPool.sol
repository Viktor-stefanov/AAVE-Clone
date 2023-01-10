// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/LibFacet.sol";

contract LendingPool {
    function deposit(
        address _pool,
        address _user,
        uint256 _amount
    ) external payable {
        LendingPoolCore core = LibFacet.getCore();
        require(
            _pool == LibFacet.facetStorage().ethAddress
                ? _user.balance >= _amount
                : ERC20(_pool).balanceOf(_user) >= _amount,
            "Insufficient token balance."
        );

        core.updateStateOnDeposit(_pool, msg.sender, _amount);
        core.transferToPool(_pool, _user, _amount);
    }

    function redeem(
        address _pool,
        address _user,
        uint256 _amount
    ) external {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        LendingPoolCore core = LibFacet.getCore();
        require(
            pool.totalLiquidity >= _amount,
            "There is not enough liquidity available to redeem."
        );
        core.updateStateOnRedeem(_pool, _amount);
        core.transferToUser(_pool, _user, _amount);
    }

    struct BorrowLocalVars {
        uint256 principalBorrowBalance;
        uint256 currentLTV;
        uint256 currentLiquidationThreshold;
        uint256 borrowFee;
        uint256 requestedBorrowAmountETH;
        uint256 amountOfCollateralNeededETH;
        uint256 userCollateralBalanceETH;
        uint256 userBorrowBalanceETH;
        uint256 userTotalFeesETH;
        uint256 borrowBalanceIncrease;
        uint256 currentReserveStableRate;
        uint256 availableLiquidity;
        uint256 reserveDecimals;
        uint256 finalUserBorrowRate;
        LibFacet.InterestRateMode rateMode;
        bool healthFactorBelowThreshold;
    }

    function borrow(
        address _pool,
        uint256 _amount,
        LibFacet.InterestRateMode _rateMode
    ) external {
        BorrowLocalVars memory vars;
        LendingPoolCore core = LibFacet.getCore();
        DataProvider dataProvider = LibFacet.getDataProvider();
        require(
            core.isPoolBorrowingEnabled(_pool),
            "Pool is not enabled for borrowing."
        );
        require(
            _rateMode == LibFacet.InterestRateMode.VARIABLE ||
                _rateMode == LibFacet.InterestRateMode.STABLE,
            "Invalid interest rate mode selected"
        );
        require(
            core.getPoolAvailableLiquidity(_pool) >= _amount,
            "There is not enough liquidity available in the pool."
        );

        (
            ,
            vars.userCollateralBalanceETH,
            vars.userBorrowBalanceETH,
            vars.userTotalFeesETH,
            vars.currentLTV,
            vars.currentLiquidationThreshold,
            ,
            vars.healthFactorBelowThreshold
        ) = dataProvider.getUserGlobalData(msg.sender);

        require(
            vars.userCollateralBalanceETH > 0,
            "The collateral balance is 0."
        );
        require(
            !vars.healthFactorBelowThreshold,
            "The borrower can already be liquidated."
        );

        vars.borrowFee = LibFacet.getFeeProvider().calculateLoanOriginationFee(
            _amount
        );

        require(vars.borrowFee > 0, "The amount to borrow is too small.");

        vars.amountOfCollateralNeededETH = LibFacet
            .getDataProvider()
            .calculateCollateralNeededInETH(
                _pool,
                _amount,
                vars.borrowFee,
                vars.userBorrowBalanceETH,
                vars.userTotalFeesETH,
                vars.currentLTV
            );

        require(
            vars.amountOfCollateralNeededETH <= vars.userCollateralBalanceETH,
            "Insufficient collateral to cover a new borrow."
        );

        /// @TODO: add stable rate checks
        (vars.finalUserBorrowRate, vars.borrowBalanceIncrease) = core
            .updateStateOnBorrow(
                _pool,
                msg.sender,
                _amount,
                vars.borrowFee,
                vars.rateMode
            );

        core.transferToUser(_pool, msg.sender, _amount);
    }
}
