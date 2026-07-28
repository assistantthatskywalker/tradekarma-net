// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title KarmaRune ($KRUNE) — Reputation Token
 * @notice ERC-20 on Base. NON-PURCHASABLE by design: tokens can only be minted
 *         by the platform MINTER (the earning engine) as reputation is earned.
 *         There is deliberately NO public mint / buy function. This is the
 *         load-bearing rule of TradeKarma: reputation is earned, never bought.
 * @dev Built on OpenZeppelin ERC20 + AccessControl. Minting rights are managed
 *      with the standard role API (`grantRole` / `revokeRole`), which emits
 *      RoleGranted / RoleRevoked on every privileged change.
 */
contract KarmaRune is ERC20, AccessControl {
    /// @notice Held by the earning engine and the migration bridge only.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice Earning events already minted, keyed on `reasonHash`. Each one can
     *         pay out at most once, forever.
     * @dev On-chain idempotency, not an off-chain convention: the settlement
     *      layer retries broadcasts it could not confirm, and a restart can
     *      replay a backlog. Both paths are safe against this mapping.
     */
    mapping(bytes32 => bool) public settled;

    event Earned(address indexed user, uint256 amount, bytes32 reasonHash);

    /**
     * @param admin holds DEFAULT_ADMIN_ROLE (multi-sig in production) and is
     *        seeded with MINTER_ROLE so the migration bridge can mint the
     *        off-chain reputation ledger on day one.
     */
    constructor(address admin) ERC20("KarmaRune", "KRUNE") {
        require(admin != address(0), "KRUNE: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, admin);
    }

    /**
     * @notice Mint KRUNE as reputation earned. Callable ONLY by the earning
     *         engine / migration bridge. `reasonHash` identifies the off-chain
     *         earning event (review, help, referral, ship) and is consumed here:
     *         one earning event mints once, and a replay reverts.
     * @dev There is no payable path anywhere in this contract — KRUNE cannot
     *      be purchased. `_mint` reverts on the zero address. The caller must
     *      derive `reasonHash` from the event's own identity (its UUID), never
     *      from the payload, or two distinct events could collide and the second
     *      would be refused.
     */
    function mintEarned(address user, uint256 amount, bytes32 reasonHash) external onlyRole(MINTER_ROLE) {
        require(!settled[reasonHash], "KRUNE: already settled");
        settled[reasonHash] = true;
        _mint(user, amount);
        emit Earned(user, amount, reasonHash);
    }
}
