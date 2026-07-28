// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice Malicious ERC-20. Once armed, the FIRST balance update (mint,
 *         transfer or transferFrom) calls back into `target` with `payload`
 *         before returning to the caller. If that re-entrant call reverts, the
 *         revert data is bubbled up verbatim so the outer transaction fails
 *         with the guard's own error (e.g. ReentrancyGuardReentrantCall).
 * @dev The arm is one-shot to avoid unbounded recursion in the unguarded case.
 */
contract ReentrantToken is ERC20 {
    uint8 private immutable _dec;

    address public target;
    bytes public payload;
    bool public armed;
    /// @notice Number of times the callback actually fired. A test asserting a
    ///         guard blocked re-entry is worthless unless this proves the hook ran.
    uint256 public callbacksFired;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _dec = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(address target_, bytes calldata payload_) external {
        target = target_;
        payload = payload_;
        armed = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (!armed) return;
        armed = false;
        callbacksFired += 1;
        bytes memory data = payload;
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}
