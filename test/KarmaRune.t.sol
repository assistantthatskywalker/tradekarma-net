// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {KarmaRune} from "../contracts/KarmaRune.sol";

contract KarmaRuneTest is Test {
    KarmaRune internal krune;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant MINTER = address(0xB0B);
    address internal constant USER = address(0xCAFE);
    address internal constant STRANGER = address(0xDEAD);

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 internal constant ADMIN_ROLE = bytes32(0);

    bytes32 internal constant REASON = keccak256("review:5-star");

    event Earned(address indexed user, uint256 amount, bytes32 reasonHash);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function setUp() public {
        krune = new KarmaRune(ADMIN);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    function test_constructor_metadataAndRoles() public view {
        assertEq(krune.name(), "KarmaRune");
        assertEq(krune.symbol(), "KRUNE");
        assertEq(krune.decimals(), 18);
        assertEq(krune.totalSupply(), 0, "KRUNE must start at zero supply - nothing pre-mined");
        assertTrue(krune.hasRole(ADMIN_ROLE, ADMIN));
        assertTrue(krune.hasRole(MINTER_ROLE, ADMIN), "admin seeded as migration-bridge minter");
    }

    function test_constructor_revertsOnZeroAdmin() public {
        vm.expectRevert("KRUNE: zero admin");
        new KarmaRune(address(0));
    }

    /// @dev Also pins the local constants used throughout this file to the
    ///      contract's own, so every other test is checking the real roles.
    function test_minterRoleConstantIsTheStandardHash() public view {
        assertEq(krune.MINTER_ROLE(), keccak256("MINTER_ROLE"));
        assertEq(krune.MINTER_ROLE(), MINTER_ROLE);
        assertEq(krune.DEFAULT_ADMIN_ROLE(), ADMIN_ROLE);
    }

    function test_supportsInterface() public view {
        assertTrue(krune.supportsInterface(type(IAccessControl).interfaceId));
        assertTrue(krune.supportsInterface(type(IERC165).interfaceId));
    }

    /*//////////////////////////////////////////////////////////////
                               MINT EARNED
    //////////////////////////////////////////////////////////////*/

    function test_mintEarned_happyPathEmitsTransferAndEarned() public {
        vm.expectEmit(true, true, false, true, address(krune));
        emit Transfer(address(0), USER, 42e18);
        vm.expectEmit(true, false, false, true, address(krune));
        emit Earned(USER, 42e18, REASON);

        vm.prank(ADMIN);
        krune.mintEarned(USER, 42e18, REASON);

        assertEq(krune.balanceOf(USER), 42e18);
        assertEq(krune.totalSupply(), 42e18);
    }

    function test_mintEarned_grantedMinterCanMint() public {
        vm.prank(ADMIN);
        krune.grantRole(MINTER_ROLE, MINTER);

        vm.prank(MINTER);
        krune.mintEarned(USER, 1e18, REASON);
        assertEq(krune.balanceOf(USER), 1e18);
    }

    function test_mintEarned_revertsForNonMinter() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, STRANGER, MINTER_ROLE
            )
        );
        vm.prank(STRANGER);
        krune.mintEarned(STRANGER, 1e18, REASON);

        assertEq(krune.totalSupply(), 0, "no supply may appear from an unauthorized mint");
    }

    /// @notice DEFAULT_ADMIN alone is not enough once MINTER_ROLE is renounced —
    ///         the admin can re-grant, but cannot mint while lacking the role.
    function test_mintEarned_revertsForAdminWithoutMinterRole() public {
        vm.prank(ADMIN);
        krune.renounceRole(MINTER_ROLE, ADMIN);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ADMIN, MINTER_ROLE)
        );
        vm.prank(ADMIN);
        krune.mintEarned(USER, 1e18, REASON);
    }

    function test_mintEarned_revertsOnZeroReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ADMIN);
        krune.mintEarned(address(0), 1e18, REASON);
    }

    function test_mintEarned_zeroAmountIsAllowedAndStillAudited() public {
        vm.expectEmit(true, false, false, true, address(krune));
        emit Earned(USER, 0, REASON);
        vm.prank(ADMIN);
        krune.mintEarned(USER, 0, REASON);
        assertEq(krune.totalSupply(), 0);
    }

    /*//////////////////////////////////////////////////////////////
        REPLAY PROTECTION — ONE EARNING EVENT, ONE MINT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice REGRESSION (was MEDIUM, replay): `reasonHash` was emitted for
     *         auditability but never recorded, so the same off-chain earning
     *         event minted again on every retry. The only thing preventing
     *         duplicates lived in an in-memory ledger that does not survive a
     *         process restart. The guard is on-chain now.
     */
    function test_mintEarned_rejectsADuplicateReasonHash() public {
        vm.startPrank(ADMIN);
        krune.mintEarned(USER, 500e18, REASON);

        vm.expectRevert("KRUNE: already settled");
        krune.mintEarned(USER, 500e18, REASON);

        // Not a per-recipient or per-amount check: the EVENT is spent.
        vm.expectRevert("KRUNE: already settled");
        krune.mintEarned(STRANGER, 1, REASON);
        vm.stopPrank();

        assertEq(krune.balanceOf(USER), 500e18, "one event, one payout");
        assertEq(krune.balanceOf(STRANGER), 0);
        assertEq(krune.totalSupply(), 500e18);
    }

    /// @notice A second minter key is not a way around the guard - this is the
    ///         hot-key blast radius the on-chain check is there to bound.
    function test_mintEarned_replayIsBlockedAcrossDifferentMinters() public {
        vm.startPrank(ADMIN);
        krune.grantRole(MINTER_ROLE, MINTER);
        krune.mintEarned(USER, 500e18, REASON);
        vm.stopPrank();

        vm.expectRevert("KRUNE: already settled");
        vm.prank(MINTER);
        krune.mintEarned(USER, 500e18, REASON);

        assertEq(krune.totalSupply(), 500e18);
    }

    function test_mintEarned_marksTheReasonSettledAndExposesIt() public {
        assertFalse(krune.settled(REASON), "unseen events start unsettled");

        vm.prank(ADMIN);
        krune.mintEarned(USER, 1e18, REASON);

        assertTrue(krune.settled(REASON), "the ledger is readable on-chain");
        assertFalse(krune.settled(keccak256("review:4-star")), "unrelated events are untouched");
    }

    /// @notice A zero-amount mint still consumes its reason, so a retry of an
    ///         already-settled no-op cannot later be replayed for value.
    function test_mintEarned_zeroAmountStillConsumesTheReason() public {
        vm.startPrank(ADMIN);
        krune.mintEarned(USER, 0, REASON);
        assertTrue(krune.settled(REASON));

        vm.expectRevert("KRUNE: already settled");
        krune.mintEarned(USER, 1_000e18, REASON);
        vm.stopPrank();

        assertEq(krune.totalSupply(), 0);
    }

    /// @notice Distinct events are unaffected - the guard blocks replays, not work.
    function testFuzz_distinctReasonsAllMintExactlyOnce(bytes32 a, bytes32 b, uint128 amount) public {
        vm.assume(a != b);
        uint256 amt = bound(amount, 1, 1e30);

        vm.startPrank(ADMIN);
        krune.mintEarned(USER, amt, a);
        krune.mintEarned(USER, amt, b);

        vm.expectRevert("KRUNE: already settled");
        krune.mintEarned(USER, amt, a);
        vm.expectRevert("KRUNE: already settled");
        krune.mintEarned(USER, amt, b);
        vm.stopPrank();

        assertEq(krune.totalSupply(), 2 * amt);
    }

    /// @notice A failed mint must not burn the reason. Otherwise an unauthorized
    ///         caller could grief a real earning event into being unpayable.
    function test_mintEarned_failedAttemptDoesNotConsumeTheReason() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, STRANGER, MINTER_ROLE
            )
        );
        vm.prank(STRANGER);
        krune.mintEarned(USER, 500e18, REASON);

        assertFalse(krune.settled(REASON), "a rejected call may not spend the event");

        vm.prank(ADMIN);
        krune.mintEarned(USER, 500e18, REASON);
        assertEq(krune.balanceOf(USER), 500e18, "the legitimate mint still lands");
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
        krune.grantRole(MINTER_ROLE, STRANGER);
    }

    function test_revokeRole_revertsForNonAdmin() public {
        vm.prank(ADMIN);
        krune.grantRole(MINTER_ROLE, MINTER);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, STRANGER, ADMIN_ROLE
            )
        );
        vm.prank(STRANGER);
        krune.revokeRole(MINTER_ROLE, MINTER);
    }

    function test_grantAndRevokeRole_emitEventsAndGateMinting() public {
        vm.expectEmit(true, true, true, false, address(krune));
        emit RoleGranted(MINTER_ROLE, MINTER, ADMIN);
        vm.prank(ADMIN);
        krune.grantRole(MINTER_ROLE, MINTER);

        vm.expectEmit(true, true, true, false, address(krune));
        emit RoleRevoked(MINTER_ROLE, MINTER, ADMIN);
        vm.prank(ADMIN);
        krune.revokeRole(MINTER_ROLE, MINTER);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, MINTER, MINTER_ROLE
            )
        );
        vm.prank(MINTER);
        krune.mintEarned(USER, 1e18, REASON);
    }

    function test_renounceRole_revertsWhenCallerIsNotTheAccount() public {
        vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        vm.prank(STRANGER);
        krune.renounceRole(MINTER_ROLE, ADMIN);
    }

    /*//////////////////////////////////////////////////////////////
        "EARNED, NEVER BOUGHT" — ABI-LEVEL PROOF
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enumerates KRUNE's ENTIRE external ABI (verified against
     *         `forge inspect KarmaRune abi` — 19 functions, no more) and proves
     *         every single entry point rejects ETH. Each function is called
     *         twice: once with value 0 where it MUST succeed, once with value
     *         1 wei where it MUST revert. The paired call is what makes this
     *         non-vacuous: the only variable is the attached ETH.
     */
    function test_noFunctionInTheAbiAcceptsEth() public {
        KarmaRune k = new KarmaRune(address(this));
        vm.deal(address(this), 10 ether);

        bytes32 minter = k.MINTER_ROLE();

        bytes[] memory calls = new bytes[](19);
        calls[0] = abi.encodeWithSignature("DEFAULT_ADMIN_ROLE()");
        calls[1] = abi.encodeWithSignature("MINTER_ROLE()");
        calls[2] = abi.encodeWithSignature("allowance(address,address)", address(this), USER);
        calls[3] = abi.encodeWithSignature("approve(address,uint256)", USER, 1);
        calls[4] = abi.encodeWithSignature("balanceOf(address)", address(this));
        calls[5] = abi.encodeWithSignature("decimals()");
        calls[6] = abi.encodeWithSignature("getRoleAdmin(bytes32)", minter);
        calls[7] = abi.encodeWithSignature("grantRole(bytes32,address)", minter, MINTER);
        calls[8] = abi.encodeWithSignature("hasRole(bytes32,address)", minter, address(this));
        calls[9] = abi.encodeWithSignature("mintEarned(address,uint256,bytes32)", address(this), 1e18, REASON);
        calls[10] = abi.encodeWithSignature("name()");
        calls[11] = abi.encodeWithSignature("renounceRole(bytes32,address)", minter, address(this));
        calls[12] = abi.encodeWithSignature("revokeRole(bytes32,address)", minter, MINTER);
        calls[13] = abi.encodeWithSignature("settled(bytes32)", REASON);
        calls[14] = abi.encodeWithSignature("supportsInterface(bytes4)", bytes4(0x01ffc9a7));
        calls[15] = abi.encodeWithSignature("symbol()");
        calls[16] = abi.encodeWithSignature("totalSupply()");
        calls[17] = abi.encodeWithSignature("transfer(address,uint256)", USER, 0);
        calls[18] = abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), USER, 0);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool paidOk,) = address(k).call{value: 1 wei}(calls[i]);
            assertFalse(paidOk, "a KRUNE function accepted ETH - reputation became purchasable");
        }
        // Same calls, no ETH: every one succeeds. Proves the loop above failed
        // on the value, not on bad calldata.
        for (uint256 i = 0; i < calls.length; i++) {
            (bool freeOk,) = address(k).call(calls[i]);
            assertTrue(freeOk, "control call without ETH should succeed");
        }
    }

    function test_plainEthTransferReverts_noReceiveNoFallback() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(krune).call{value: 1 ether}("");
        assertFalse(ok, "KRUNE must not have a receive() - no ETH may enter the reputation token");
        assertEq(address(krune).balance, 0);
    }

    function test_unknownSelectorReverts_noFallbackHidingABuyPath() public {
        (bool ok,) = address(krune).call(abi.encodeWithSignature("buy()"));
        assertFalse(ok);
        (ok,) = address(krune).call(abi.encodeWithSignature("mint(address,uint256)", USER, 1e18));
        assertFalse(ok, "there is no public mint(address,uint256) on KRUNE");
        (ok,) = address(krune).call(abi.encodeWithSignature("purchase(uint256)", 1e18));
        assertFalse(ok);
        assertEq(krune.totalSupply(), 0);
    }

    /// @notice The only supply-increasing path is mintEarned, and it is role-gated.
    ///         Fuzzed over arbitrary callers to make the claim general.
    function testFuzz_onlyMinterRoleCanEverIncreaseSupply(address caller, uint256 amount) public {
        vm.assume(caller != ADMIN && caller != address(0));
        amount = bound(amount, 1, 1e30);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, MINTER_ROLE)
        );
        vm.prank(caller);
        krune.mintEarned(caller, amount, REASON);
        assertEq(krune.totalSupply(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC20 BEHAVIOUR
    //////////////////////////////////////////////////////////////*/

    function test_transferAndTransferFrom() public {
        vm.prank(ADMIN);
        krune.mintEarned(USER, 10e18, REASON);

        vm.prank(USER);
        assertTrue(krune.transfer(STRANGER, 4e18));
        assertEq(krune.balanceOf(USER), 6e18);
        assertEq(krune.balanceOf(STRANGER), 4e18);

        vm.prank(USER);
        krune.approve(address(this), 6e18);
        assertTrue(krune.transferFrom(USER, STRANGER, 6e18));
        assertEq(krune.balanceOf(USER), 0);
        assertEq(krune.balanceOf(STRANGER), 10e18);
    }

    function test_transfer_revertsOnInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER, 0, 1));
        vm.prank(USER);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        krune.transfer(STRANGER, 1);
    }
}
