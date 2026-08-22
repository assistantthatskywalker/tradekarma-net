// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {KarmaRune} from "../../contracts/KarmaRune.sol";

/**
 * @notice Reaches KarmaRune's `_update` hook directly, bypassing the public
 *         `transfer` / `transferFrom` guards.
 * @dev Without this the soulbound rule could only be tested at the ABI surface,
 *      which proves the three overrides revert and says nothing about the hook
 *      underneath them — the one that would still be load-bearing if a future
 *      version of the token grew an internal transfer path.
 */
contract KarmaRuneHarness is KarmaRune {
    constructor(address admin) KarmaRune(admin) {}

    function internalUpdate(address from, address to, uint256 value) external {
        _update(from, to, value);
    }
}
