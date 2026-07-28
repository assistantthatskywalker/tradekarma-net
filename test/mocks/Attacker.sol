// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Attacker EOA-substitute. Holds tokens, so it is a legitimate staker /
 *         redeemer, and forwards arbitrary calldata to `victim`. Used as the
 *         re-entry target so that the nested call arrives with the SAME
 *         msg.sender as the outer call — i.e. the real double-drain shape,
 *         not a call from the token contract.
 */
contract Attacker {
    address public immutable victim;

    constructor(address victim_) {
        victim = victim_;
    }

    function approve(address token, address spender, uint256 amount) external {
        IERC20(token).approve(spender, amount);
    }

    /// @dev Bubbles the victim's revert data so the outer tx fails with it.
    function exec(bytes calldata data) external returns (bytes memory) {
        (bool ok, bytes memory ret) = victim.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        return ret;
    }
}
