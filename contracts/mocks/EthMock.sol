pragma solidity 0.8.17;

import "../libraries/LibFacet.sol";

contract EthMock {
    function transferEthToUser(address _user, uint256 _amount) public payable {
        (bool success, ) = _user.call{value: _amount}("");
        require(success, "Error while sending ETH.");
    }

    receive() external payable {}
}
