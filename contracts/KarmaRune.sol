// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title KarmaRune ($KRUNE) — Soulbound Reputation Token
 * @notice ERC-20 on Base. NON-PURCHASABLE by design: tokens can only be minted
 *         by the platform MINTER (the earning engine) as reputation is earned.
 *         There is deliberately NO public mint / buy function, and — since v2 —
 *         no transfer path either. This is the load-bearing rule of TradeKarma:
 *         reputation is earned, never bought.
 * @dev Built on OpenZeppelin ERC20 + AccessControl. Minting rights are managed
 *      with the standard role API (`grantRole` / `revokeRole`), which emits
 *      RoleGranted / RoleRevoked on every privileged change.
 *
 *      SOULBOUND. `_update` rejects every holder-to-holder movement, and the
 *      three ERC-20 entry points that would otherwise imply one — `transfer`,
 *      `transferFrom`, `approve` — revert outright rather than leaving a
 *      surface that looks usable and is not. Enforcing the rule at mint alone
 *      (v1) put a computable price on reputation: a whale with capital and no
 *      history simply bought KRUNE OTC and walked through the staking gate.
 *
 *      Two consequences the rest of the system depends on:
 *      1. A holder's balance is monotonically non-decreasing. Nothing here
 *         burns, and no transfer can leave a wallet, so `balanceOf` only ever
 *         goes up. `Staking` relies on exactly this to REFERENCE a staker's
 *         KRUNE instead of escrowing it — escrow is impossible against a token
 *         that cannot be transferred.
 *      2. `allowance` is permanently zero for every pair, so no integrator can
 *         hold a standing claim on someone's reputation.
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
    /// @notice Immutable recipient/amount commitment for reconciliation after process loss.
    mapping(bytes32 => bytes32) public settlementDigest;

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
        settlementDigest[reasonHash] = keccak256(abi.encode(user, amount));
        _mint(user, amount);
        emit Earned(user, amount, reasonHash);
    }

    /**
     * @dev The soulbound rule itself. Every balance change in OpenZeppelin's
     *      ERC20 — `_mint`, `_burn`, `_transfer` — funnels through here, so this
     *      one require covers paths that do not exist yet as well as the ones
     *      that do. `from == 0` is a mint and stays open; `to == 0` would be a
     *      burn and is left open because no burn path is exposed, and blocking
     *      an unreachable case would only add a branch nobody can exercise.
     *      Anything else is a holder-to-holder movement and is refused.
     */
    function _update(address from, address to, uint256 value) internal override {
        require(from == address(0) || to == address(0), "KRUNE: soulbound");
        super._update(from, to, value);
    }

    /// @notice Disabled. KRUNE is soulbound — reputation is not transferable.
    function transfer(address, uint256) public pure override returns (bool) {
        revert("KRUNE: soulbound");
    }

    /// @notice Disabled. KRUNE is soulbound — reputation is not transferable.
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("KRUNE: soulbound");
    }

    /**
     * @notice Disabled. An allowance on a soulbound token can never be spent, so
     *         granting one would only mislead — a UI that saw `approve` succeed
     *         would report a working integration that cannot exist.
     */
    function approve(address, uint256) public pure override returns (bool) {
        revert("KRUNE: soulbound");
    }
}
