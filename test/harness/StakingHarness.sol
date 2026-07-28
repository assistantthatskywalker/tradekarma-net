// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Staking} from "../../contracts/Staking.sol";

/**
 * @notice Exposes Staking's internal pure math so the geometric mean and the
 *         yield formula can be fuzzed over the full uint256 range without
 *         needing token balances that large to exist.
 */
contract StakingHarness is Staking {
    constructor(address _krune, address _kdex, address _kshrd, address owner_)
        Staking(_krune, _kdex, _kshrd, owner_)
    {}

    function geometricMean(uint256 a, uint256 b) external pure returns (uint256) {
        return _geometricMean(a, b);
    }

    function yieldFor(uint256 geometric, uint256 elapsed) external pure returns (uint256) {
        return _yieldFor(geometric, elapsed);
    }

    /// @notice The PREVIOUS implementation, kept only so a test can prove it
    ///         overflows exactly where the current one survives.
    function naiveGeometricMean(uint256 a, uint256 b) external pure returns (uint256) {
        return Math.sqrt(a * b);
    }
}
