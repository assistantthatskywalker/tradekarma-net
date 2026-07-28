// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Unguarded counter used as a positive control: proves ReentrantToken's
///         callback really fires, so a blocked re-entry is a real block.
contract ReentrancyProbe {
    uint256 public pings;

    function ping() external {
        pings += 1;
    }
}
