// SPDX-License-Identifier: No-License
pragma solidity 0.8.17;

import "./libraries/WadRayMath.sol";

contract FeeProvider {
    using WadRayMath for uint256;

    uint256 internal constant originationFeePercentage = 0.0025 * 1e18;

    function calculateLoanOriginationFee(uint256 _amount)
        external
        pure
        returns (uint256)
    {
        return _amount.wadMul(originationFeePercentage);
    }
}
