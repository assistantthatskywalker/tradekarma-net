// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title KarmaShard ($KSHRD) — Yield Token
 * @notice ERC-20 on Base. The claim ticket produced by staking: Staking mints
 *         KSHRD for accrued yield when a position is closed, and the Treasury
 *         burns it when the holder redeems for USDC or KDEX. Supply therefore
 *         equals exactly the yield that has been earned and not yet redeemed.
 * @dev Minting is restricted to the Staking contract and burning to the
 *      Treasury, both via AccessControl roles granted after deployment. Once
 *      that wiring is done, `lockRoles()` seals the role table forever, so the
 *      "only Staking can mint" claim above stops being a promise about a key
 *      and becomes a fact anyone can read off-chain state to verify.
 */
contract KarmaShard is ERC20, AccessControl {
    /// @notice Held by the Staking contract only.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @notice Held by the Treasury only — redemption destroys the shard.
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    /// @notice True once `lockRoles()` has run. Never returns to false.
    bool public rolesLocked;

    /// @notice Emitted once, ever. Role administration is over from here.
    event RolesLocked();

    /**
     * @param admin holds DEFAULT_ADMIN_ROLE (multi-sig in production) and grants
     *        MINTER_ROLE to Staking / BURNER_ROLE to Treasury once both are deployed,
     *        then calls `lockRoles()` to give that power up permanently.
     */
    constructor(address admin) ERC20("KarmaShard", "KSHRD") {
        require(admin != address(0), "KSHRD: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Mint yield. Callable ONLY by the Staking contract.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @notice Burn redeemed yield. Callable ONLY by the Treasury, and only up to
     *         the allowance the holder has granted it — the standard
     *         ERC20Burnable semantics.
     * @dev Two independent authorizations are required, and neither substitutes
     *      for the other: the role says the protocol permits this contract to
     *      burn at all, the allowance says the holder permits it to burn THEIR
     *      shards. Without the allowance leg a BURNER_ROLE holder could destroy
     *      any balance outright, with no consent and no payout.
     */
    function burnFrom(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    /**
     * @notice PERMANENTLY seals role administration. THIS CANNOT BE UNDONE — no
     *         function, no role, no owner and no upgrade path reverses it, because
     *         the contract is not upgradeable and `rolesLocked` is never written
     *         false anywhere in this file.
     * @dev After this call `grantRole`, `revokeRole` and `renounceRole` all revert
     *      for every role including DEFAULT_ADMIN_ROLE, so the set of minters and
     *      burners is frozen exactly as it stands. Call it only once Staking holds
     *      MINTER_ROLE and Treasury holds BURNER_ROLE and both addresses have been
     *      verified — locking before the grants lands would leave KSHRD unmintable
     *      forever, and every staker's yield permanently unclaimable.
     */
    function lockRoles() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!rolesLocked, "KSHRD: roles already locked");
        rolesLocked = true;
        emit RolesLocked();
    }

    /// @dev Every role grant in AccessControl funnels through here, including
    ///      `grantRole`. Sealed by `lockRoles`.
    function _grantRole(bytes32 role, address account) internal override returns (bool) {
        require(!rolesLocked, "KSHRD: roles locked");
        return super._grantRole(role, account);
    }

    /// @dev Likewise for `revokeRole` and `renounceRole`. Revocation is sealed
    ///      too: an admin who could still revoke MINTER_ROLE from Staking could
    ///      brick every future yield mint at will.
    function _revokeRole(bytes32 role, address account) internal override returns (bool) {
        require(!rolesLocked, "KSHRD: roles locked");
        return super._revokeRole(role, account);
    }
}
