// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "../interfaces/IDiamondCut.sol";
import "../interfaces/IDiamond.sol";

library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION =
        keccak256("diamonds.standart.diamond.storage");

    struct Facet {
        address facetAddress;
        uint16 selectorIndex;
    }

    struct Storage {
        address contractOwner;
        mapping(bytes4 => Facet) selectorToFacet;
        bytes4[] selectors;
        mapping(bytes4 => uint256) selectorToIndex;
    }

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event DiamondCut(
        IDiamond.FacetCut[] _diamondCut,
        address _init,
        bytes _calldata
    );

    function diamondStorage() internal pure returns (Storage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function setContractOwner(address _newOwner) internal {
        Storage storage ds = diamondStorage();
        address prevOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(prevOwner, _newOwner);
    }

    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCuts,
        address _init,
        bytes memory _calldata
    ) internal {
        for (
            uint256 facetIndex = 0;
            facetIndex < _diamondCuts.length;
            facetIndex++
        ) {
            bytes4[] memory selectors = _diamondCuts[facetIndex]
                .functionSelectors;
            address facetAddress = _diamondCuts[facetIndex].facetAddress;
            require(selectors.length != 0, "No function selectors provided.");

            IDiamondCut.FacetCutAction action = _diamondCuts[facetIndex].action;
            if (action == IDiamond.FacetCutAction.Add)
                addFunctions(facetAddress, selectors);
            else if (action == IDiamond.FacetCutAction.Replace)
                replaceFunctions(facetAddress, selectors);
            else if (action == IDiamond.FacetCutAction.Remove)
                removeFunctions(facetAddress, selectors);
            else revert("Invalid action.");
            emit DiamondCut(_diamondCuts, _init, _calldata);
            initializeDiamondCut(_init, _calldata);
        }
    }

    function addFunctions(address _facet, bytes4[] memory _selectors) internal {
        require(
            _facet != address(0),
            "Can't add functions to facet with address 0."
        );
        enforceHasContractCode(_facet, "LibDiamond: Add Facet has no code.");
        Storage storage ds = diamondStorage();
        uint16 selectorCount = uint16(_selectors.length);
        for (uint256 i = 0; i < _selectors.length; i++) {
            bytes4 selector = _selectors[i];
            address oldFacetAddress = ds.selectorToFacet[selector].facetAddress;
            require(
                oldFacetAddress == address(0),
                "Can't add an already existing function."
            );
            ds.selectorToFacet[selector] = Facet(_facet, selectorCount);
            ds.selectors.push(selector);
            ds.selectorToIndex[selector] = ++selectorCount;
        }
    }

    function replaceFunctions(address _facet, bytes4[] memory _selectors)
        internal
    {
        require(
            _facet != address(0),
            "Can't replace functions to facet with address 0."
        );
        enforceHasContractCode(
            _facet,
            "LibDiamond: Replace facet has no code."
        );
        Storage storage ds = diamondStorage();
        for (uint256 i = 0; i < _selectors.length; i++) {
            bytes4 selector = _selectors[i];
            address oldFacetAddress = ds.selectorToFacet[selector].facetAddress;
            require(
                oldFacetAddress != address(0),
                "Can't replace a non existing function."
            );
            require(oldFacetAddress != address(this), "Function is immutable.");
            /// @dev If we remove this check upgrades from the same contract will be possible.
            require(
                oldFacetAddress != _facet,
                "Can't replace facet with same facet."
            );
            ds.selectorToFacet[selector].facetAddress = _facet;
        }
    }

    function removeFunctions(address _facet, bytes4[] memory _selectors)
        internal
    {
        require(
            _facet != address(0),
            "Can't remove functions from facet with address 0."
        );
        enforceHasContractCode(_facet, "LibDiamond: Remove facet has no code.");
        Storage storage ds = diamondStorage();
        uint16 selectorCount = uint16(_selectors.length);
        for (uint256 i = 0; i < _selectors.length; i++) {
            bytes4 selector = _selectors[i];
            Facet memory oldFacet = ds.selectorToFacet[selector];
            require(oldFacet.facetAddress != address(0), "No facet to remove.");
            require(
                oldFacet.facetAddress != address(this),
                "Can't remove an immutable function."
            );
            /// @TODO: Decypher the next 6 lines of code
            if (oldFacet.selectorIndex != --selectorCount) {
                bytes4 lastSelector = ds.selectors[selectorCount];
                ds.selectors[oldFacet.selectorIndex] = lastSelector;
                ds.selectorToFacet[lastSelector].selectorIndex = oldFacet
                    .selectorIndex;
            }
            ds.selectors.pop();
            delete ds.selectorToFacet[selector];
        }
    }

    function initializeDiamondCut(address _init, bytes memory _calldata)
        internal
    {
        if (_init == address(0)) return;
        enforceHasContractCode(_init, "LibDiamond: _init address has no code");
        (bool success, bytes memory error) = _init.delegatecall(_calldata);
        if (!success) {
            if (error.length > 0) {
                assembly {
                    let returndata_size := mload(error)
                    revert(add(32, error), returndata_size)
                }
            } else revert();
        }
    }

    function enforceIsContractOwner() internal view {
        require(
            msg.sender == diamondStorage().contractOwner,
            "Only contract owner has permission for this action."
        );
    }

    function enforceHasContractCode(
        address _contract,
        string memory _errMessage
    ) internal view {
        uint256 contractSize;
        assembly {
            contractSize := extcodesize(_contract)
        }
        require(contractSize != 0, _errMessage);
    }

    function contractOwner() internal view returns (address) {
        return diamondStorage().contractOwner;
    }
}
