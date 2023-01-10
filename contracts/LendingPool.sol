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
        if (_pool == LibFacet.facetStorage().ethAddress)
            return depositEth(_pool, _user, _amount);

        require(
            ERC20(_pool).balanceOf(_user) >= _amount,
            "Insufficient token balance."
        );

        LibFacet.getCore().updateStateOnDeposit(_pool, msg.sender, _amount);
        ERC20(_pool).transferFrom(_user, address(this), _amount);
    }

    function depositEth(
        address _pool,
        address _user,
        uint256 _amount
    ) internal {
        require(_user.balance >= _amount, "Insufficient ETH balance.");
        LibFacet.getCore().updateStateOnDeposit(_pool, _user, _amount);
        (bool success, ) = _user.call{value: _amount}("");
        require(success, "Error while sending eth.");
    }

    //function redeem(
    //    address _pool,
    //    address _user,
    //    uint256 _amount
    //) external {
    //    LibFacet.Pool storage pool = LibFacet.lpcStorage().pools[_pool];
    //    LendingPoolCore core = LibFacet.getCore();
    //    require(
    //        pool.user[_user].liquidityProvided >= _amount,
    //        "Can't redeem more than has been deposited."
    //    );
    //    require(
    //        pool.totalLiquidity >= _amount,
    //        "Pool does not have enough resources at the current moment."
    //    );
    //    core.updateCumulativeIndexes(pool);
    //    uint256 ethAmount = core.getEthValue(_pool, _amount);
    //    require(
    //        core.getHealthFactor(
    //            pool.user[_user].collateralEthBalance - ethAmount,
    //            pool.user[_user].liquidationThreshold,
    //            pool.user[_user].compoundedBorrowBalance
    //        ) > 1,
    //        "Cannot redeem as it will cause your loan health factor to drop below 1."
    //    );
    //    pool.user[_user].collateralEthBalance -= ethAmount;
    //    pool.user[_user].liquidityProvided -= _amount;
    //    pool.totalLiquidity -= _amount;
    //    core.updatePoolInterestRates(pool);
    //    if (_pool == LibFacet.facetStorage().ethAddress) {
    //        (bool success, ) = _user.call{value: _amount}("");
    //        require(success, "Error transfering ETH.");
    //    } else ERC20(_pool).transferFrom(address(this), _user, _amount);
    //}

    function borrow(
        address _pool,
        address _user,
        uint256 _amount
    ) external payable {}
}
