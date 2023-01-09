// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PriceFeed {
    address internal owner;
    mapping(address => AggregatorV3Interface) internal priceFeeds;

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the owner of this smart contract can execute this action."
        );
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function addAssetOracle(address _asset, address _oracle)
        external
        onlyOwner
    {
        priceFeeds[_asset] = AggregatorV3Interface(_oracle);
    }

    function getAssetPrice(address _asset) external view returns (uint256) {
        (, int256 price, , , ) = priceFeeds[_asset].latestRoundData();
        return uint256(price);
    }
}
