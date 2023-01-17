pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract UsdcMock is ERC20 {
    constructor(address _to) ERC20("UsdcMock", "USDCM") {
        _mint(_to, 10000 ether);
    }

    function test() external pure returns (uint256) {
        return 5;
    }
}
