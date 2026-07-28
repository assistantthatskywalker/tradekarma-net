// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {KarmaShard} from "../contracts/KarmaShard.sol";

contract KarmaShardTest is Test {
    KarmaShard internal kshrd;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant STAKING = address(0x57A4);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant USER = address(0xCAFE);
    address internal constant STRANGER = address(0xDEAD);

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 internal constant ADMIN_ROLE = bytes32(0);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event RolesLocked();

    function setUp() public {
        kshrd = new KarmaShard(ADMIN);
        vm.startPrank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, STAKING);
        kshrd.grantRole(BURNER_ROLE, TREASURY);
        vm.stopPrank();
    }

    function test_constructor_metadataAndRoles() public view {
        assertEq(kshrd.name(), "KarmaShard");
        assertEq(kshrd.symbol(), "KSHRD");
        assertEq(kshrd.decimals(), 18);
        assertEq(kshrd.totalSupply(), 0);
        assertTrue(kshrd.hasRole(ADMIN_ROLE, ADMIN));
        assertFalse(kshrd.hasRole(MINTER_ROLE, ADMIN), "admin is NOT seeded as minter - only Staking mints");
        assertFalse(kshrd.hasRole(BURNER_ROLE, ADMIN), "admin is NOT seeded as burner - only Treasury burns");
    }

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert("KSHRD: zero admin");
        new KarmaShard(address(0));
    }

    /// @dev Also pins the local constants used throughout this file to the
    ///      contract's own, so every other test is checking the real roles.
    function test_roleConstants() public view {
        assertEq(kshrd.MINTER_ROLE(), keccak256("MINTER_ROLE"));
        assertEq(kshrd.BURNER_ROLE(), keccak256("BURNER_ROLE"));
        assertEq(kshrd.DEFAULT_ADMIN_ROLE(), bytes32(0));
        assertEq(kshrd.MINTER_ROLE(), MINTER_ROLE);
        assertEq(kshrd.BURNER_ROLE(), BURNER_ROLE);
        assertEq(kshrd.DEFAULT_ADMIN_ROLE(), ADMIN_ROLE);
        assertTrue(kshrd.MINTER_ROLE() != kshrd.BURNER_ROLE(), "mint and burn must be separable powers");
    }

    /*//////////////////////////////////////////////////////////////
                                   MINT
    //////////////////////////////////////////////////////////////*/

    function test_mint_byMinterRole() public {
        vm.expectEmit(true, true, false, true, address(kshrd));
        emit Transfer(address(0), USER, 7e18);
        vm.prank(STAKING);
        kshrd.mint(USER, 7e18);

        assertEq(kshrd.balanceOf(USER), 7e18);
        assertEq(kshrd.totalSupply(), 7e18);
    }

    function test_mint_revertsForNonMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, STRANGER, MINTER_ROLE
            )
        );
        vm.prank(STRANGER);
        kshrd.mint(STRANGER, 1e18);
    }

    function test_mint_revertsForAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ADMIN, MINTER_ROLE)
        );
        vm.prank(ADMIN);
        kshrd.mint(USER, 1e18);
    }

    /// @notice BURNER_ROLE must not be a back door into minting.
    function test_mint_revertsForBurnerRoleHolder() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, TREASURY, MINTER_ROLE
            )
        );
        vm.prank(TREASURY);
        kshrd.mint(TREASURY, 1e18);
    }

    function test_mint_revertsOnZeroReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(STAKING);
        kshrd.mint(address(0), 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                                 BURN FROM
    //////////////////////////////////////////////////////////////*/

    function test_burnFrom_spendsTheHoldersAllowance() public {
        vm.startPrank(STAKING);
        kshrd.mint(USER, 10e18);
        vm.stopPrank();

        vm.prank(USER);
        kshrd.approve(TREASURY, 4e18);

        vm.expectEmit(true, true, false, true, address(kshrd));
        emit Transfer(USER, address(0), 4e18);
        vm.prank(TREASURY);
        kshrd.burnFrom(USER, 4e18);

        assertEq(kshrd.balanceOf(USER), 6e18);
        assertEq(kshrd.totalSupply(), 6e18);
        assertEq(kshrd.allowance(USER, TREASURY), 0, "the allowance was consumed, not reusable");
    }

    /// @notice The consent leg: holding BURNER_ROLE is not enough on its own.
    function test_burnFrom_revertsWithoutAllowance() public {
        vm.prank(STAKING);
        kshrd.mint(USER, 10e18);

        assertEq(kshrd.allowance(USER, TREASURY), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, TREASURY, 0, 1)
        );
        vm.prank(TREASURY);
        kshrd.burnFrom(USER, 1);

        assertEq(kshrd.balanceOf(USER), 10e18, "not one wei may burn without the holder's say-so");
    }

    /// @notice An approval is a ceiling, not a blank cheque.
    function test_burnFrom_cannotExceedTheAllowance() public {
        vm.prank(STAKING);
        kshrd.mint(USER, 10e18);
        vm.prank(USER);
        kshrd.approve(TREASURY, 3e18);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, TREASURY, 3e18, 3e18 + 1)
        );
        vm.prank(TREASURY);
        kshrd.burnFrom(USER, 3e18 + 1);

        vm.prank(TREASURY);
        kshrd.burnFrom(USER, 3e18);
        assertEq(kshrd.balanceOf(USER), 7e18);
    }

    function test_burnFrom_revertsForNonBurner() public {
        vm.prank(STAKING);
        kshrd.mint(USER, 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, STRANGER, BURNER_ROLE
            )
        );
        vm.prank(STRANGER);
        kshrd.burnFrom(USER, 1e18);
    }

    /// @notice MINTER_ROLE must not be a back door into burning other people's shards.
    function test_burnFrom_revertsForMinterRoleHolder() public {
        vm.prank(STAKING);
        kshrd.mint(USER, 10e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, STAKING, BURNER_ROLE
            )
        );
        vm.prank(STAKING);
        kshrd.burnFrom(USER, 1e18);
    }

    function test_burnFrom_revertsOnInsufficientBalance() public {
        vm.prank(STAKING);
        kshrd.mint(USER, 1e18);
        vm.prank(USER);
        kshrd.approve(TREASURY, type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER, 1e18, 2e18));
        vm.prank(TREASURY);
        kshrd.burnFrom(USER, 2e18);
    }

    /// @notice The holder cannot burn their own shards - only the Treasury can,
    ///         and only as part of a redemption that pays them out.
    function test_holderCannotSelfBurn() public {
        vm.prank(STAKING);
        kshrd.mint(USER, 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, USER, BURNER_ROLE)
        );
        vm.prank(USER);
        kshrd.burnFrom(USER, 1e18);

        (bool ok,) = address(kshrd).call(abi.encodeWithSignature("burn(uint256)", 1e18));
        assertFalse(ok, "no ERC20Burnable self-burn is exposed");
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    function test_grantRole_revertsForNonAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, STRANGER, ADMIN_ROLE
            )
        );
        vm.prank(STRANGER);
        kshrd.grantRole(MINTER_ROLE, STRANGER);
    }

    function test_revokeRole_disablesMinting() public {
        vm.prank(ADMIN);
        kshrd.revokeRole(MINTER_ROLE, STAKING);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, STAKING, MINTER_ROLE
            )
        );
        vm.prank(STAKING);
        kshrd.mint(USER, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                                FINDINGS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice REGRESSION (was MEDIUM, centralization): `burnFrom` used to take no
     *         allowance - "the role itself is the authorization" - so
     *         DEFAULT_ADMIN could grant BURNER_ROLE to any address and that
     *         address could destroy any holder's yield claim outright, with no
     *         payout and no consent. The allowance leg closes it: the role still
     *         says WHO may burn, the allowance says WHOSE shards and HOW MANY.
     */
    function test_burnerRoleHolderCannotWipeShardsWithoutConsent() public {
        address rogue = address(0xF00D);

        vm.prank(STAKING);
        kshrd.mint(USER, 1_000e18);

        vm.prank(ADMIN);
        kshrd.grantRole(BURNER_ROLE, rogue);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, rogue, 0, 1_000e18)
        );
        vm.prank(rogue);
        kshrd.burnFrom(USER, 1_000e18);

        assertEq(kshrd.balanceOf(USER), 1_000e18, "the holder's yield claim survives");
        assertEq(kshrd.totalSupply(), 1_000e18);

        // An approval to the Treasury is not an approval to the rogue.
        vm.prank(USER);
        kshrd.approve(TREASURY, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, rogue, 0, 1)
        );
        vm.prank(rogue);
        kshrd.burnFrom(USER, 1);
    }

    /*//////////////////////////////////////////////////////////////
        ROLE LOCK — ONE-WAY SEAL ON THE RUG-PULL SURFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The C-01 drain: DEFAULT_ADMIN self-grants MINTER_ROLE, mints KSHRD
     *         from nothing and redeems it against the Treasury. `lockRoles()`
     *         makes the first step impossible, permanently.
     */
    function test_lockRoles_blocksAdminFromSelfGrantingMinterRole() public {
        // Before the lock, the drain is one transaction away.
        uint256 snap = vm.snapshotState();
        vm.startPrank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, ADMIN);
        kshrd.mint(ADMIN, 1_000_000e18);
        vm.stopPrank();
        assertEq(kshrd.balanceOf(ADMIN), 1_000_000e18, "control: unlocked admin can conjure shards");
        vm.revertToState(snap);

        vm.prank(ADMIN);
        kshrd.lockRoles();

        vm.expectRevert("KSHRD: roles locked");
        vm.prank(ADMIN);
        kshrd.grantRole(MINTER_ROLE, ADMIN);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ADMIN, MINTER_ROLE)
        );
        vm.prank(ADMIN);
        kshrd.mint(ADMIN, 1);
        assertEq(kshrd.totalSupply(), 0);
    }

    function test_lockRoles_setsTheFlagAndEmits() public {
        assertFalse(kshrd.rolesLocked());

        vm.expectEmit(false, false, false, false, address(kshrd));
        emit RolesLocked();
        vm.prank(ADMIN);
        kshrd.lockRoles();

        assertTrue(kshrd.rolesLocked(), "the seal is readable on-chain by anyone");
    }

    /// @notice Revocation is sealed too - otherwise an admin could still brick
    ///         every future yield mint by cutting Staking off.
    function test_lockRoles_blocksRevokeAndRenounce() public {
        vm.prank(ADMIN);
        kshrd.lockRoles();

        vm.expectRevert("KSHRD: roles locked");
        vm.prank(ADMIN);
        kshrd.revokeRole(MINTER_ROLE, STAKING);

        vm.expectRevert("KSHRD: roles locked");
        vm.prank(STAKING);
        kshrd.renounceRole(MINTER_ROLE, STAKING);

        vm.expectRevert("KSHRD: roles locked");
        vm.prank(ADMIN);
        kshrd.renounceRole(ADMIN_ROLE, ADMIN);

        // The wiring that existed at lock time still works, untouched.
        vm.prank(STAKING);
        kshrd.mint(USER, 1e18);
        assertEq(kshrd.balanceOf(USER), 1e18);
    }

    /// @notice There is no second call, no unlock, and no non-admin path in.
    function test_lockRoles_isIrreversibleAndAdminOnly() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, STRANGER, ADMIN_ROLE)
        );
        vm.prank(STRANGER);
        kshrd.lockRoles();

        vm.startPrank(ADMIN);
        kshrd.lockRoles();
        vm.expectRevert("KSHRD: roles already locked");
        kshrd.lockRoles();
        vm.stopPrank();

        assertTrue(kshrd.rolesLocked());
        (bool ok,) = address(kshrd).call(abi.encodeWithSignature("unlockRoles()"));
        assertFalse(ok, "no unlock function exists");
        (ok,) = address(kshrd).call(abi.encodeWithSignature("setRolesLocked(bool)", false));
        assertFalse(ok);
    }

    /// @notice Locking does not freeze the token itself - only its role table.
    function test_lockRoles_leavesMintAndBurnWorking() public {
        vm.prank(STAKING);
        kshrd.mint(USER, 10e18);
        vm.prank(USER);
        kshrd.approve(TREASURY, 10e18);

        vm.prank(ADMIN);
        kshrd.lockRoles();

        vm.prank(STAKING);
        kshrd.mint(USER, 5e18);
        vm.prank(TREASURY);
        kshrd.burnFrom(USER, 10e18);

        assertEq(kshrd.balanceOf(USER), 5e18);
    }

    function test_rejectsEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(kshrd).call{value: 1 ether}("");
        assertFalse(ok);
        (ok,) = address(kshrd).call{value: 1 wei}(abi.encodeWithSignature("totalSupply()"));
        assertFalse(ok);
    }

    function testFuzz_mintBurnRoundTripConservesSupply(uint256 mintAmt, uint256 burnAmt) public {
        mintAmt = bound(mintAmt, 0, type(uint128).max);
        burnAmt = bound(burnAmt, 0, mintAmt);

        vm.prank(STAKING);
        kshrd.mint(USER, mintAmt);
        vm.prank(USER);
        kshrd.approve(TREASURY, burnAmt);
        vm.prank(TREASURY);
        kshrd.burnFrom(USER, burnAmt);

        assertEq(kshrd.totalSupply(), mintAmt - burnAmt);
        assertEq(kshrd.balanceOf(USER), mintAmt - burnAmt);
    }

    function testFuzz_onlyMinterRoleCanIncreaseSupply(address caller, uint256 amount) public {
        vm.assume(caller != STAKING);
        amount = bound(amount, 1, 1e30);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, MINTER_ROLE)
        );
        vm.prank(caller);
        kshrd.mint(caller, amount);
        assertEq(kshrd.totalSupply(), 0);
    }
}
