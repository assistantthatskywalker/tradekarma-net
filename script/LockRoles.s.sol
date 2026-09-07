// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {KarmaShard} from "../contracts/KarmaShard.sol";
import {Staking} from "../contracts/Staking.sol";
import {Treasury} from "../contracts/Treasury.sol";

/**
 * @title LockRoles — the one-way seal on KarmaShard's role table
 * @notice STOP. `KarmaShard.lockRoles()` CANNOT BE UNDONE. There is no
 *         function, no role, no owner and no upgrade path that reverses it.
 *         After it lands, `grantRole`, `revokeRole` and `renounceRole` revert
 *         for every role forever, and the set of KSHRD minters and burners is
 *         frozen exactly as it stands at that block.
 *
 *         Run this only when all of the following are true:
 *           - `Verify.s.sol` passed against this exact deployment, on this chain;
 *           - Staking holds MINTER_ROLE and Treasury holds BURNER_ROLE;
 *           - you have independently confirmed those two addresses are the
 *             Staking and Treasury you intend to run forever.
 *
 *         Locking before the grants land makes KSHRD permanently unmintable and
 *         every staker's yield permanently unclaimable. Locking with the wrong
 *         Staking address does the same thing, quietly.
 *
 * @dev This is a separate script on purpose: nothing in the deploy path can
 *      reach it, no flag on `Deploy.s.sol` turns it on, and it cannot run as a
 *      side effect of anything. It re-derives the two grants from the chain and
 *      cross-checks the addresses against the contracts themselves before it
 *      will broadcast, and it refuses to run at all without an exact
 *      confirmation phrase in the environment.
 *
 *      What the seal buys: it closes audit C-01. Today the KSHRD admin can
 *      self-grant MINTER_ROLE, mint unlimited shards from nothing, and redeem
 *      them for 100% of the Treasury. After the lock that path does not exist
 *      for anyone, including a compromised multi-sig.
 *
 *      What the seal costs, and the audit does not spell this out: it also
 *      makes the minter and burner sets permanent, which means there can never
 *      be a Staking v2 or a Treasury v2 on this KSHRD. A replacement Treasury
 *      could never obtain BURNER_ROLE, so outstanding KSHRD could never be
 *      redeemed against it; a replacement Staking could never mint. Combined
 *      with audit M-03 (the Treasury has no migration path and cannot release
 *      USDC except through `redeem`), locking converts every remaining
 *      economic finding — H-01, H-02, H-04 — into a permanent one. Lock when
 *      the economics are settled, not when the wiring is.
 */
contract LockRoles is Script {
    /// @dev Typed in full, exactly, or the script does nothing. The phrase is
    ///      long and unpleasant to type by design — nobody reaches it by
    ///      autocompleting a shell history entry.
    bytes32 internal constant CONFIRMATION = keccak256(bytes("I UNDERSTAND THIS IS IRREVERSIBLE"));

    function run() external {
        KarmaShard kshrd = KarmaShard(_envAddress("KSHRD_ADDRESS"));
        Staking staking = Staking(_envAddress("STAKING_ADDRESS"));
        Treasury treasury = Treasury(_envAddress("TREASURY_ADDRESS"));

        string memory confirmation = vm.envOr("CONFIRM_LOCK_ROLES", string(""));
        require(
            keccak256(bytes(confirmation)) == CONFIRMATION,
            'LOCK: refusing. Set CONFIRM_LOCK_ROLES="I UNDERSTAND THIS IS IRREVERSIBLE" to proceed'
        );

        console2.log("== KarmaShard.lockRoles() -- IRREVERSIBLE ==");
        console2.log("chain id", block.chainid);
        console2.log("KSHRD   ", address(kshrd));
        console2.log("Staking ", address(staking));
        console2.log("Treasury", address(treasury));

        require(address(kshrd).code.length > 0, "LOCK: KSHRD_ADDRESS has no code");
        require(address(staking).code.length > 0, "LOCK: STAKING_ADDRESS has no code");
        require(address(treasury).code.length > 0, "LOCK: TREASURY_ADDRESS has no code");
        require(!kshrd.rolesLocked(), "LOCK: roles are already locked -- nothing to do");

        // Independent verification of the two addresses, from the other side.
        // `hasRole` alone would happily confirm a role granted to the wrong
        // contract; this asks Staking and Treasury whether they are in fact
        // wired to THIS KarmaShard, which a stale or mistyped address is not.
        require(address(staking.kshrd()) == address(kshrd), "LOCK: STAKING_ADDRESS is not wired to this KSHRD");
        require(address(treasury.kshrd()) == address(kshrd), "LOCK: TREASURY_ADDRESS is not wired to this KSHRD");

        require(address(staking.treasury()) == address(treasury), "LOCK: Staking treasury mismatch");
        require(kshrd.getRoleMemberCount(kshrd.MINTER_ROLE()) == 1, "LOCK: unexpected minter count");
        require(kshrd.getRoleMemberCount(kshrd.BURNER_ROLE()) == 1, "LOCK: unexpected burner count");
        bytes32 minter = kshrd.MINTER_ROLE();
        bytes32 burner = kshrd.BURNER_ROLE();

        require(
            kshrd.hasRole(minter, address(staking)),
            "LOCK: Staking does NOT hold MINTER_ROLE. Locking now would make KSHRD unmintable forever"
        );
        require(
            kshrd.hasRole(burner, address(treasury)),
            "LOCK: Treasury does NOT hold BURNER_ROLE. Locking now would make KSHRD unredeemable forever"
        );
        require(
            kshrd.hasRole(kshrd.DEFAULT_ADMIN_ROLE(), msg.sender),
            "LOCK: the sender does not hold DEFAULT_ADMIN_ROLE on KSHRD"
        );

        console2.log("");
        console2.log("preconditions met:");
        console2.log("  Staking holds MINTER_ROLE and is wired to this KSHRD");
        console2.log("  Treasury holds BURNER_ROLE and is wired to this KSHRD");
        console2.log("  these two addresses are about to become permanent");
        console2.log("");
        console2.log("If ADMIN_ADDRESS is a Safe, do not broadcast from here. Execute this calldata from the Safe:");
        console2.log("  to  ", address(kshrd));
        console2.logBytes(abi.encodeCall(KarmaShard.lockRoles, ()));
        console2.log("");

        vm.startBroadcast();
        kshrd.lockRoles();
        vm.stopBroadcast();

        require(kshrd.rolesLocked(), "LOCK: lockRoles() did not take effect");
        console2.log("== KSHRD role table sealed. rolesLocked = true, permanently. ==");
    }

    function _envAddress(string memory key) internal view returns (address value) {
        value = vm.envOr(key, address(0));
        require(value != address(0), string.concat("LOCK: ", key, " is unset or zero"));
    }
}
