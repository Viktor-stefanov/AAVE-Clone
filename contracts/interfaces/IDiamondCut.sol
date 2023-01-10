// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./IDiamond.sol";

interface IDiamondCut is IDiamond {
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;
}
