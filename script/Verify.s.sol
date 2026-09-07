// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {KarmaRune} from "../contracts/KarmaRune.sol";
import {KarmaDex} from "../contracts/KarmaDex.sol";
import {KarmaShard} from "../contracts/KarmaShard.sol";
import {Staking} from "../contracts/Staking.sol";
import {Treasury} from "../contracts/Treasury.sol";

/**
 * @title Verify — read-only post-deployment gate
 * @notice Reads the live chain and asserts that the deployment is wired the way
 *         `Deploy.s.sol` intended: the right roles on the right addresses, no
 *         roles on the wrong ones, both owners at the multi-sig, Staking and
 *         Treasury pointing at the same three tokens, `usdcScale` matching the
 *         real USDC contract, and `rolesLocked` in the state you expect.
 *         Broadcasts nothing and signs nothing.
 * @dev Every check reports rather than reverting on the first failure, so one
 *      run tells you everything that is wrong instead of making you fix and
 *      re-run six times. The script reverts at the end if anything failed, so
 *      it is still safe to use as a CI gate or a `&&` in a runbook.
 *
 *      One honest limitation, and it matters: OpenZeppelin's AccessControl
 *      cannot enumerate role holders, so `hasRole` can prove that the intended
 *      address holds a role but never that it is the ONLY holder. This script
 *      therefore checks the intended holders positively and the plausible
 *      mistakes negatively — the deploy key, the multi-sig, and the two
 *      contracts swapped for each other. To close the gap completely, scan the
 *      RoleGranted logs; the exact `cast logs` command is in script/README.md.
 */
contract Verify is Script {
    uint256 internal failures;
    uint256 internal checks;

    function run() external {
        address adminAddr = _envAddress("ADMIN_ADDRESS");
        address bridge = _envAddress("EARNING_ENGINE_BRIDGE");
        address usdcAddr = _envAddress("USDC_ADDRESS");
        uint256 kdexSupply = vm.envOr("KDEX_INITIAL_SUPPLY", uint256(0));

        KarmaRune krune = KarmaRune(_envAddress("KRUNE_ADDRESS"));
        KarmaDex kdex = KarmaDex(_envAddress("KDEX_ADDRESS"));
        KarmaShard kshrd = KarmaShard(_envAddress("KSHRD_ADDRESS"));
        Staking staking = Staking(_envAddress("STAKING_ADDRESS"));
        Treasury treasury = Treasury(_envAddress("TREASURY_ADDRESS"));

        // Optional. When set, the retired deploy key is asserted to hold
        // nothing anywhere — the single most consequential thing to get wrong,
        // because that key spent the deployment holding KSHRD's admin role.
        address deployer = vm.envOr("DEPLOYER_ADDRESS", address(0));
        bool expectLocked = vm.envOr("EXPECT_ROLES_LOCKED", false);

        console2.log("== verifying TradeKarma deployment ==");
        console2.log("chain id", block.chainid);
        console2.log("");

        _bytecode(krune, kdex, kshrd, staking, treasury);
        _tokens(krune, kdex, kshrd, kdexSupply);
        _kshrdRoles(kshrd, staking, treasury, adminAddr, deployer, expectLocked);
        _kruneRoles(krune, bridge, adminAddr, deployer);
        _staking(staking, krune, kdex, kshrd, adminAddr);
        _treasury(treasury, kdex, kshrd, usdcAddr, adminAddr);

        console2.log("");
        console2.log("checks  ", checks);
        console2.log("failures", failures);
        require(failures == 0, "VERIFY: deployment is NOT correctly wired -- see FAIL lines above. Do NOT lock roles.");
        console2.log("== deployment verified ==");
    }

    // ---------------------------------------------------------------- checks

    /// @dev An address with no code is either the wrong network, a typo, or a
    ///      deployment that reverted. Everything below would read zeros.
    function _bytecode(KarmaRune krune, KarmaDex kdex, KarmaShard kshrd, Staking staking, Treasury treasury) internal {
        console2.log("-- bytecode --");
        _check(address(krune).code.length > 0, "KRUNE has code");
        _check(address(kdex).code.length > 0, "KDEX has code");
        _check(address(kshrd).code.length > 0, "KSHRD has code");
        _check(address(staking).code.length > 0, "Staking has code");
        _check(address(treasury).code.length > 0, "Treasury has code");
    }

    /// @dev Catches the address that was pasted into the wrong variable: the
    ///      symbols are read back off-chain, so KRUNE_ADDRESS pointing at the
    ///      KDEX deployment fails here rather than silently later.
    function _tokens(KarmaRune krune, KarmaDex kdex, KarmaShard kshrd, uint256 kdexSupply) internal {
        console2.log("-- token identity --");
        _check(_sameString(krune.symbol(), "KRUNE"), "KRUNE_ADDRESS reports symbol KRUNE");
        _check(_sameString(kdex.symbol(), "KDEX"), "KDEX_ADDRESS reports symbol KDEX");
        _check(_sameString(kshrd.symbol(), "KSHRD"), "KSHRD_ADDRESS reports symbol KSHRD");
        // Treasury's KDEX payout leg assumes 18 decimals and never checks it
        // (audit L-02); the assumption is only true because we deployed KDEX.
        _check(kdex.decimals() == 18, "KDEX has 18 decimals");
        _check(kshrd.decimals() == 18, "KSHRD has 18 decimals");
        _checkEq(kdex.totalSupply(), kdexSupply, "KDEX total supply matches KDEX_INITIAL_SUPPLY");
        // KSHRD supply is the outstanding yield claim. It should be zero on a
        // fresh deployment; anything else means shards exist that no staker
        // earned (audit C-01).
        _checkEq(kshrd.totalSupply(), 0, "KSHRD total supply is zero (no yield minted yet)");
    }

    /// @dev The two grants the system cannot run without, and the four holders
    ///      it must not have. `Treasury` holding MINTER or `Staking` holding
    ///      BURNER is the swapped-argument mistake; either would be sealed in
    ///      permanently by `lockRoles()`.
    function _kshrdRoles(
        KarmaShard kshrd,
        Staking staking,
        Treasury treasury,
        address adminAddr,
        address deployer,
        bool expectLocked
    ) internal {
        console2.log("-- KSHRD roles --");
        bytes32 minter = kshrd.MINTER_ROLE();
        bytes32 burner = kshrd.BURNER_ROLE();
        bytes32 defaultAdmin = kshrd.DEFAULT_ADMIN_ROLE();

        _check(kshrd.getRoleMemberCount(minter) == 1, "exactly one KSHRD minter");
        _check(kshrd.getRoleMemberCount(burner) == 1, "exactly one KSHRD burner");
        _check(kshrd.hasRole(minter, address(staking)), "MINTER_ROLE held by Staking");
        _check(kshrd.hasRole(burner, address(treasury)), "BURNER_ROLE held by Treasury");
        _check(!kshrd.hasRole(minter, address(treasury)), "MINTER_ROLE NOT held by Treasury");
        _check(!kshrd.hasRole(burner, address(staking)), "BURNER_ROLE NOT held by Staking");
        _check(!kshrd.hasRole(minter, adminAddr), "MINTER_ROLE NOT held by the multi-sig");
        _check(!kshrd.hasRole(burner, adminAddr), "BURNER_ROLE NOT held by the multi-sig");
        _check(kshrd.hasRole(defaultAdmin, adminAddr), "DEFAULT_ADMIN_ROLE held by the multi-sig");

        if (deployer != address(0)) {
            _check(!kshrd.hasRole(minter, deployer), "MINTER_ROLE NOT held by the retired deploy key");
            _check(!kshrd.hasRole(burner, deployer), "BURNER_ROLE NOT held by the retired deploy key");
            _check(!kshrd.hasRole(defaultAdmin, deployer), "DEFAULT_ADMIN_ROLE NOT held by the retired deploy key");
        }

        _check(kshrd.rolesLocked() == expectLocked, "rolesLocked matches EXPECT_ROLES_LOCKED");
        if (!kshrd.rolesLocked()) {
            console2.log("       note: roles are still mutable. The multi-sig can grant KSHRD MINTER_ROLE to itself");
            console2.log("       and drain the Treasury (audit C-01). LockRoles.s.sol closes this, irreversibly.");
        }
    }

    /// @dev KRUNE keeps a live admin forever — the bridge key has to be
    ///      rotatable. What must not survive the deployment is the deploy key's
    ///      constructor-seeded MINTER_ROLE: KRUNE has no supply cap, so that
    ///      key would be an unbounded reputation printer (audit H-05).
    function _kruneRoles(KarmaRune krune, address bridge, address adminAddr, address deployer) internal {
        console2.log("-- KRUNE roles --");
        bytes32 minter = krune.MINTER_ROLE();
        bytes32 defaultAdmin = krune.DEFAULT_ADMIN_ROLE();

        _check(krune.hasRole(minter, bridge), "MINTER_ROLE held by the earning-engine bridge");
        _check(krune.hasRole(defaultAdmin, adminAddr), "DEFAULT_ADMIN_ROLE held by the multi-sig");
        _check(!krune.hasRole(minter, adminAddr), "MINTER_ROLE NOT held by the multi-sig");
        _check(!krune.hasRole(defaultAdmin, bridge), "DEFAULT_ADMIN_ROLE NOT held by the bridge");

        if (deployer != address(0)) {
            _check(!krune.hasRole(minter, deployer), "MINTER_ROLE NOT held by the retired deploy key");
            _check(!krune.hasRole(defaultAdmin, deployer), "DEFAULT_ADMIN_ROLE NOT held by the retired deploy key");
        }
    }

    /// @dev Staking's constructor takes (krune, kdex, kshrd) while Treasury's
    ///      takes (usdc, kdex, kshrd). The orders differ by one slot, and both
    ///      addresses are immutable, so a swap is unfixable and invisible until
    ///      the first unstake.
    function _staking(Staking staking, KarmaRune krune, KarmaDex kdex, KarmaShard kshrd, address adminAddr) internal {
        console2.log("-- Staking --");
        _checkAddr(address(staking.krune()), address(krune), "krune()");
        _checkAddr(address(staking.kdex()), address(kdex), "kdex()");
        _checkAddr(address(staking.kshrd()), address(kshrd), "kshrd()");
        _checkAddr(staking.owner(), adminAddr, "owner()");
        _checkAddr(address(staking.treasury()), _envAddress("TREASURY_ADDRESS"), "staking treasury()");
        _check(!staking.paused(), "not paused");
    }

    /// @dev `usdcScale` is immutable and set from `USDC.decimals()` at
    ///      construction. Recomputing it here from the live USDC contract is the
    ///      one check that proves the Treasury was pointed at the real
    ///      stablecoin and not at something that merely answers `decimals()`.
    function _treasury(Treasury treasury, KarmaDex kdex, KarmaShard kshrd, address usdcAddr, address adminAddr)
        internal
    {
        console2.log("-- Treasury --");
        _checkAddr(address(treasury.usdc()), usdcAddr, "usdc()");
        _checkAddr(address(treasury.kdex()), address(kdex), "kdex()");
        _checkAddr(address(treasury.kshrd()), address(kshrd), "kshrd()");
        _checkAddr(treasury.owner(), adminAddr, "owner()");

        uint8 usdcDecimals = IERC20Metadata(usdcAddr).decimals();
        _checkEq(treasury.usdcScale(), 10 ** (18 - usdcDecimals), "usdcScale() matches USDC decimals");
        console2.log("       USDC decimals", usdcDecimals);
    }

    // --------------------------------------------------------------- helpers

    function _check(bool ok, string memory label) internal {
        checks++;
        if (ok) {
            console2.log(string.concat("  ok   ", label));
        } else {
            failures++;
            console2.log(string.concat("  FAIL ", label));
        }
    }

    function _checkAddr(address actual, address expected, string memory label) internal {
        _check(actual == expected, label);
        if (actual != expected) {
            console2.log("         expected", expected);
            console2.log("         actual  ", actual);
        }
    }

    function _checkEq(uint256 actual, uint256 expected, string memory label) internal {
        _check(actual == expected, label);
        if (actual != expected) {
            console2.log("         expected", expected);
            console2.log("         actual  ", actual);
        }
    }

    function _sameString(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _envAddress(string memory key) internal view returns (address value) {
        value = vm.envOr(key, address(0));
        require(value != address(0), string.concat("VERIFY: ", key, " is unset or zero"));
    }
}
