pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract UsdcMock is ERC20 {
    constructor(address _to) ERC20("UsdcMock", "USDCM") {
        _mint(_to, 10000 ether);
    }

    function customApprove(
        address _owner,
        address _spender,
        uint256 _amount
    ) public {
        _approve(_owner, _spender, _amount);
    }
}
