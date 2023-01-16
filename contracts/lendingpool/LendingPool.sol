// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../libraries/LibFacet.sol";
import "hardhat/console.sol";

contract LendingPool {
    function deposit(
        address _pool,
        address _user,
        uint256 _amount
    ) external payable {
        require(
            _pool == LibFacet.facetStorage().ethAddress
                ? _user.balance >= _amount
                : ERC20(_pool).balanceOf(_user) >= _amount,
            "Insufficient token balance."
        );

        LendingPoolCore(address(this)).updateStateOnDeposit(
            _pool,
            msg.sender,
            _amount
        );
    }

    function redeem(
        address _pool,
        address _user,
        uint256 _amount
    ) external {
        console.log("redeeming");
        LendingPoolCore core = LendingPoolCore(address(this));
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        require(
            pool.totalLiquidity >= _amount,
            "There is not enough liquidity available to redeem."
        );
        core.updateStateOnRedeem(
            _pool,
            msg.sender,
            _amount,
            _amount == pool.users[_user].liquidityProvided
        );
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
        LendingPoolCore core = LendingPoolCore(address(this));
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
        ) = DataProvider(address(this)).getUserGlobalData(msg.sender);

        require(
            vars.userCollateralBalanceETH > 0,
            "The collateral balance is 0."
        );
        require(
            !vars.healthFactorBelowThreshold,
            "The borrower can already be liquidated."
        );

        vars.borrowFee = FeeProvider(address(this)).calculateLoanOriginationFee(
            _amount
        );

        require(vars.borrowFee > 0, "The amount to borrow is too small.");

        vars.amountOfCollateralNeededETH = DataProvider(address(this))
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

        /// TODO: add stable rate checks
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

    struct RepayLocalVars {
        uint256 principalBorrowBalance;
        uint256 compoundedBorrowBalance;
        uint256 borrowBalanceIncrease;
        bool isETH;
        uint256 paybackAmount;
        uint256 paybackAmountMinusFee;
        uint256 currentStableRate;
        uint256 originationFee;
    }

    function repay(address _pool, uint256 _amount) external payable {
        LendingPoolCore core = LendingPoolCore(address(this));
        RepayLocalVars memory vars;

        (
            vars.principalBorrowBalance,
            vars.compoundedBorrowBalance,
            vars.borrowBalanceIncrease
        ) = core.getUserBorrowBalances(_pool, msg.sender);

        vars.originationFee = core.getUserOriginationFee(_pool, msg.sender);
        vars.isETH = LibFacet.facetStorage().ethAddress == _pool;

        require(
            vars.compoundedBorrowBalance > 0,
            "The user does nto have any borrow pending."
        );

        /// @note default behavior is to repay the full loan
        vars.paybackAmount = vars.compoundedBorrowBalance + vars.originationFee;
        if (_amount < vars.paybackAmount) vars.paybackAmount = _amount;

        require(
            !vars.isETH || msg.value >= vars.paybackAmount,
            "Insufficient msg.value send for the repayment."
        );

        if (vars.paybackAmount <= vars.originationFee) {
            core.updateStateOnRepay(
                _pool,
                msg.sender,
                0,
                vars.paybackAmount,
                vars.borrowBalanceIncrease,
                false
            );
            core.transferToFeeCollector{
                value: vars.isETH ? vars.paybackAmount : 0
            }(_pool, msg.sender, vars.paybackAmount);
            return;
        }

        vars.paybackAmountMinusFee = vars.paybackAmount - vars.originationFee;
        console.log("amount:");
        console.log(_amount);

        console.log("please");
        console.log(vars.paybackAmount);
        console.log(vars.compoundedBorrowBalance);
        console.log(vars.principalBorrowBalance);
        console.log(vars.originationFee);
        core.updateStateOnRepay(
            _pool,
            msg.sender,
            vars.paybackAmountMinusFee,
            vars.originationFee,
            vars.borrowBalanceIncrease,
            vars.compoundedBorrowBalance == vars.paybackAmountMinusFee
        );

        if (vars.originationFee > 0) {
            core.transferToFeeCollector{
                value: vars.isETH ? vars.originationFee : 0
            }(_pool, msg.sender, vars.originationFee);
        }

        core.transferToPool{
            value: vars.isETH ? msg.value - vars.originationFee : 0
        }(_pool, msg.sender, vars.paybackAmountMinusFee);
    }

    function setUserUsePoolAsCollateral(address _pool, bool _useAsCollateral)
        external
    {
        LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
        require(
            pool.users[msg.sender].liquidityProvided > 0,
            "User does not have any liquidity deposited."
        );
        require(
            !pool.users[msg.sender].useAsCollateral,
            "User deposit is already used as collateral."
        );
        LendingPoolCore(address(this)).setUserUsePoolAsCollateralInternal(
            _pool,
            msg.sender,
            _useAsCollateral
        );
    }

    /// TODO: why do we take the origination fee from the compounded balance and not the principal amount?
    function calculateUserAmountToRepay(address _pool, address _user)
        public
        view
        returns (uint256)
    {
        (
            uint256 principalBorrowBalance,
            uint256 compoundedBorrowBalance,

        ) = LendingPoolCore(address(this)).getUserBorrowBalances(_pool, _user);
        uint256 originationFee = FeeProvider(address(this))
            .calculateLoanOriginationFee(compoundedBorrowBalance);

        return compoundedBorrowBalance + originationFee;
    }

    function test(address _pool, address _user) public view {
        (
            uint256 currentBorrowBalance,
            uint256 principalBorrowBalance,
            uint256 liquidityRate,
            uint256 originationFee,
            uint256 variableBorrowIndex,
            uint256 lastUpdatedTimestamp,
            LibFacet.InterestRateMode borrowRate,
            bool usageAsCollateralEnabled
        ) = DataProvider(address(this)).getUserPoolData(_pool, _user);
        console.log("\n");
        console.log(principalBorrowBalance);
        console.log(currentBorrowBalance);
        console.log(currentBorrowBalance - principalBorrowBalance);
        console.log(currentBorrowBalance + originationFee);
        console.log(originationFee);
        console.log(liquidityRate);
        console.log(variableBorrowIndex);
    }
}
