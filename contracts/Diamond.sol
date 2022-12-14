// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./libraries/LibDiamond.sol";
import "./interfaces/IDiamond.sol";

contract Diamond {
    struct DiamondArgs {
        address owner;
        address init;
        bytes initCalldata;
    }

    constructor(
        IDiamond.FacetCut[] memory _diamondCuts,
        DiamondArgs memory _args
    ) {
        LibDiamond.setContractOwner(_args.owner);
        LibDiamond.diamondCut(_diamondCuts, _args.init, _args.initCalldata);
    }

    fallback() external payable {
        LibDiamond.Storage storage ds = LibDiamond.diamondStorage();
        address facet = ds.selectorToFacet[msg.sig].facetAddress;
        require(facet != address(0), "Function not found.");
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), facet, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)
            switch result
            case 0 {
                revert(ptr, size)
            }
            default {
                return(ptr, size)
            }
        }
    }

    receive() external payable {}
}
