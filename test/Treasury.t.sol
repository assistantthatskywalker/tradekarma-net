// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {KarmaDex} from "../contracts/KarmaDex.sol";
import {KarmaShard} from "../contracts/KarmaShard.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TreasuryTest is Test {
    MockERC20 internal usdc;
    KarmaDex internal kdex;
    KarmaShard internal kshrd;
    Treasury internal treasury;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant OWNER = address(0xB0B);
    address internal constant KDEX_TREASURY = address(0x7EA5);
    address internal constant USER = address(0xCAFE);
    address internal constant STRANGER = address(0xDEAD);

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 internal constant ADMIN_ROLE = bytes32(0);

    uint256 internal constant KDEX_SUPPLY = 100_000_000e18;
    uint256 internal constant USDC_FLOAT = 1_000_000e6; // 1,000,000.00 USDC
    uint256 internal constant KDEX_FLOAT = 1_000_000e18;

    event Redeemed(address indexed user, uint256 kshrd, bool asUsdc, uint256 paid);
    event FeeDeposited(address indexed from, uint256 usdcAmount);
    event TokenRecovered(address indexed token, address indexed to, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        kdex = new KarmaDex(KDEX_SUPPLY, KDEX_TREASURY);
        kshrd = new KarmaShard(ADMIN);
        treasury = new Treasury(address(usdc), address(kdex), address(kshrd), OWNER);

        vm.startPrank(ADMIN);
        kshrd.grantRole(BURNER_ROLE, address(treasury));
        kshrd.grantRole(MINTER_ROLE, address(this)); // stand-in for Staking
        vm.stopPrank();

        usdc.mint(address(treasury), USDC_FLOAT);
        vm.prank(KDEX_TREASURY);
        assertTrue(kdex.transfer(address(treasury), KDEX_FLOAT));
    }

    /// @dev The approval is part of redeeming now: the burn spends the holder's
    ///      allowance, so a redemption the holder never authorized cannot happen.
    ///      `test_redeem_revertsWithoutApproval` proves this setup is load-bearing.
    function _giveShards(address to, uint256 amount) internal {
        kshrd.mint(to, amount);
        vm.prank(to);
        kshrd.approve(address(treasury), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTION
    //////////////////////////////////////////////////////////////*/

    function test_constructor_wiringAndScale() public view {
        assertEq(address(treasury.usdc()), address(usdc));
        assertEq(address(treasury.kdex()), address(kdex));
        assertEq(address(treasury.kshrd()), address(kshrd));
        assertEq(treasury.owner(), OWNER);
        assertEq(treasury.usdcScale(), 1e12, "10 ** (18 - 6)");
        assertEq(treasury.KDEX_KEEPBACK_BONUS_BPS(), 1000);
    }

    function test_constructor_revertsOnZeroTokens() public {
        vm.expectRevert("TREAS: zero token");
        new Treasury(address(0), address(kdex), address(kshrd), OWNER);
        vm.expectRevert("TREAS: zero token");
        new Treasury(address(usdc), address(0), address(kshrd), OWNER);
        vm.expectRevert("TREAS: zero token");
        new Treasury(address(usdc), address(kdex), address(0), OWNER);
    }

    function test_constructor_revertsWhenUsdcHasMoreThan18Decimals() public {
        MockERC20 weird = new MockERC20("Weird", "WRD", 19);
        vm.expectRevert("TREAS: USDC decimals > 18");
        new Treasury(address(weird), address(kdex), address(kshrd), OWNER);
    }

    function testFuzz_usdcScaleTracksTheStablecoinDecimals(uint8 dec) public {
        dec = uint8(bound(dec, 0, 18));
        MockERC20 stable = new MockERC20("Stable", "STBL", dec);
        Treasury t = new Treasury(address(stable), address(kdex), address(kshrd), OWNER);
        assertEq(t.usdcScale(), 10 ** (18 - uint256(dec)));
    }

    /*//////////////////////////////////////////////////////////////
                               DEPOSIT FEES
    //////////////////////////////////////////////////////////////*/

    function test_depositFees_movesUsdcAndEmits() public {
        usdc.mint(STRANGER, 500e6);
        vm.startPrank(STRANGER);
        usdc.approve(address(treasury), 500e6);

        vm.expectEmit(true, false, false, true, address(treasury));
        emit FeeDeposited(STRANGER, 500e6);
        treasury.depositFees(500e6);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(treasury)), USDC_FLOAT + 500e6);
        assertEq(usdc.balanceOf(STRANGER), 0);
    }

    function test_depositFees_revertsWithoutAllowance() public {
        usdc.mint(STRANGER, 1e6);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(treasury), 0, 1e6)
        );
        vm.prank(STRANGER);
        treasury.depositFees(1e6);
    }

    /*//////////////////////////////////////////////////////////////
        DECIMAL CORRECTNESS — THE ONE-TRILLION-DOLLAR BUG
    //////////////////////////////////////////////////////////////*/

    /// @notice 1 KSHRD must pay exactly 1.00 USDC = 1_000_000 base units.
    ///         If usdcScale were missing this would pay 1e18 units = $1 trillion.
    function test_redeem_oneKshrdPaysExactlyOneUsdc() public {
        _giveShards(USER, 1e18);

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Redeemed(USER, 1e18, true, 1_000_000);
        vm.prank(USER);
        uint256 paid = treasury.redeem(1e18, true);

        assertEq(paid, 1_000_000, "exactly 1.00 USDC");
        assertEq(usdc.balanceOf(USER), 1_000_000);
        assertEq(usdc.balanceOf(address(treasury)), USDC_FLOAT - 1_000_000);
        assertEq(kshrd.balanceOf(USER), 0);
        assertEq(kshrd.totalSupply(), 0, "the shard is destroyed on redemption");
    }

    function test_redeem_usdcAmountTable() public {
        uint256[6] memory shards =
            [uint256(1e18), 2e18, 1_000e18, 1e12, 123_456_789e12, 493_150_683_628_800_000];
        uint256[6] memory expected = [uint256(1_000_000), 2_000_000, 1_000_000_000, 1, 123_456_789, 493_150];
        address[6] memory holders =
            [address(0xD01), address(0xD02), address(0xD03), address(0xD04), address(0xD05), address(0xD06)];

        for (uint256 i = 0; i < shards.length; i++) {
            address holder = holders[i];
            _giveShards(holder, shards[i]);
            vm.prank(holder);
            uint256 paid = treasury.redeem(shards[i], true);
            assertEq(paid, expected[i], "USDC payout must scale by exactly 1e12");
        }
    }

    /// @notice Sub-unit dust must revert and burn NOTHING. Otherwise a holder
    ///         with 0.0000009 KSHRD could be silently drained.
    function test_redeem_subUnitDustRevertsAndBurnsNothing() public {
        _giveShards(USER, 1e12 - 1);

        vm.expectRevert("TREAS: below one USDC unit");
        vm.prank(USER);
        treasury.redeem(1e12 - 1, true);

        assertEq(kshrd.balanceOf(USER), 1e12 - 1, "not a single wei of KSHRD may be burned");
        assertEq(kshrd.totalSupply(), 1e12 - 1);
        assertEq(usdc.balanceOf(USER), 0);
        assertEq(usdc.balanceOf(address(treasury)), USDC_FLOAT);
    }

    function test_redeem_exactlyOneUsdcUnitIsTheBoundary() public {
        _giveShards(USER, 1e12);
        vm.prank(USER);
        uint256 paid = treasury.redeem(1e12, true);
        assertEq(paid, 1, "1e12 KSHRD == 1 USDC base unit == $0.000001");
        assertEq(kshrd.balanceOf(USER), 0);
    }

    /// @notice Partial dust: only the paid-for portion is burned, the remainder
    ///         stays with the holder.
    function test_redeem_burnsOnlyWhatWasPaidFor() public {
        _giveShards(USER, 1_500_000_000_000); // 1.5e12 -> 1 USDC unit + 0.5e12 dust

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Redeemed(USER, 1e12, true, 1);
        vm.prank(USER);
        uint256 paid = treasury.redeem(1_500_000_000_000, true);

        assertEq(paid, 1);
        assertEq(kshrd.balanceOf(USER), 500_000_000_000, "dust stays with the holder");
        assertEq(kshrd.totalSupply(), 500_000_000_000);
    }

    function testFuzz_usdcRedemptionRoundTrips(uint256 amount) public {
        amount = bound(amount, 1e12, 1e24); // >= 1 USDC unit, <= 1e6 KSHRD
        _giveShards(USER, amount);
        uint256 supplyBefore = kshrd.totalSupply();

        vm.prank(USER);
        uint256 paid = treasury.redeem(amount, true);

        uint256 burned = supplyBefore - kshrd.totalSupply();
        assertEq(usdc.balanceOf(USER), paid);
        assertEq(paid * treasury.usdcScale(), burned, "every burned shard bought exactly one USDC unit");
        assertLe(burned, amount, "never burn more than requested");
        assertLt(amount - burned, treasury.usdcScale(), "leftover is strictly sub-unit dust");
        assertEq(kshrd.balanceOf(USER), amount - burned);
    }

    function testFuzz_redemptionIsExactAcrossAnyStablecoinDecimals(uint8 dec, uint256 whole) public {
        dec = uint8(bound(dec, 0, 18));
        whole = bound(whole, 1, 1e6);

        MockERC20 stable = new MockERC20("Stable", "STBL", dec);
        Treasury t = new Treasury(address(stable), address(kdex), address(kshrd), OWNER);
        vm.prank(ADMIN);
        kshrd.grantRole(BURNER_ROLE, address(t));
        stable.mint(address(t), type(uint128).max);

        uint256 shards = whole * 1e18;
        _giveShards(USER, shards);
        vm.prank(USER);
        kshrd.approve(address(t), type(uint256).max);
        vm.prank(USER);
        uint256 paid = t.redeem(shards, true);

        assertEq(paid, whole * (10 ** uint256(dec)), "N KSHRD must always pay N whole stablecoins");
    }

    /*//////////////////////////////////////////////////////////////
                              REDEEM — KDEX
    //////////////////////////////////////////////////////////////*/

    function test_redeem_asKdexPaysTenPercentBonus() public {
        _giveShards(USER, 100e18);

        vm.expectEmit(true, false, false, true, address(treasury));
        emit Redeemed(USER, 100e18, false, 110e18);
        vm.prank(USER);
        uint256 paid = treasury.redeem(100e18, false);

        assertEq(paid, 110e18, "+10% keepback bonus");
        assertEq(kdex.balanceOf(USER), 110e18);
        assertEq(kdex.balanceOf(address(treasury)), KDEX_FLOAT - 110e18);
        assertEq(kshrd.balanceOf(USER), 0, "the full amount is burned - no dust in the KDEX path");
        assertEq(usdc.balanceOf(address(treasury)), USDC_FLOAT, "USDC untouched");
    }

    function test_redeem_asKdexHasNoDustFloor() public {
        _giveShards(USER, 1);
        vm.prank(USER);
        uint256 paid = treasury.redeem(1, false);
        assertEq(paid, 1, "1 wei KSHRD -> 1 wei KDEX (bonus truncates to 0)");
        assertEq(kshrd.balanceOf(USER), 0);
    }

    function testFuzz_kdexRedemptionAlwaysPaysAmountPlusTenPercent(uint256 amount) public {
        amount = bound(amount, 1, 100_000e18);
        _giveShards(USER, amount);
        vm.prank(USER);
        uint256 paid = treasury.redeem(amount, false);
        assertEq(paid, amount + amount / 10);
        assertEq(kshrd.balanceOf(USER), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM — REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_redeem_revertsOnZeroAmount() public {
        vm.expectRevert("TREAS: zero amount");
        vm.prank(USER);
        treasury.redeem(0, true);

        vm.expectRevert("TREAS: zero amount");
        vm.prank(USER);
        treasury.redeem(0, false);
    }

    function test_redeem_revertsOnInsufficientTreasuryUsdc() public {
        uint256 tooMuch = (USDC_FLOAT + 1) * 1e12;
        _giveShards(USER, tooMuch);

        vm.expectRevert("TREAS: insufficient USDC");
        vm.prank(USER);
        treasury.redeem(tooMuch, true);

        assertEq(kshrd.balanceOf(USER), tooMuch, "a failed payout must not burn shards");
    }

    function test_redeem_revertsOnInsufficientTreasuryKdex() public {
        uint256 tooMuch = KDEX_FLOAT; // +10% pushes past the float
        _giveShards(USER, tooMuch);

        vm.expectRevert("TREAS: insufficient KDEX");
        vm.prank(USER);
        treasury.redeem(tooMuch, false);

        assertEq(kshrd.balanceOf(USER), tooMuch);
    }

    function test_redeem_revertsWhenHolderHasTooFewShards() public {
        _giveShards(USER, 1e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, USER, 1e18, 2e18));
        vm.prank(USER);
        treasury.redeem(2e18, true);
    }

    /// @notice Redemption cannot burn someone else's shards: burnFrom always
    ///         targets msg.sender. STRANGER is given a full allowance of their
    ///         OWN shards, so the revert has to come from the balance, not from
    ///         the approval - otherwise this would pass vacuously.
    function test_redeem_cannotBurnAnotherHoldersShards() public {
        _giveShards(USER, 5e18);
        vm.prank(STRANGER);
        kshrd.approve(address(treasury), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, STRANGER, 0, 5e18));
        vm.prank(STRANGER);
        treasury.redeem(5e18, true);
        assertEq(kshrd.balanceOf(USER), 5e18);
    }

    /**
     * @notice Consent, end to end: a redemption the holder never approved cannot
     *         burn their shards, on either payout path.
     */
    function test_redeem_revertsWithoutApproval() public {
        kshrd.mint(USER, 5e18); // deliberately NOT via _giveShards - no approval

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(treasury), 0, 5e18
            )
        );
        vm.prank(USER);
        treasury.redeem(5e18, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(treasury), 0, 5e18
            )
        );
        vm.prank(USER);
        treasury.redeem(5e18, false);

        assertEq(kshrd.balanceOf(USER), 5e18);
        assertEq(usdc.balanceOf(address(treasury)), USDC_FLOAT);
    }

    /// @notice The allowance is a ceiling on the redemption, not just on the burn.
    function test_redeem_isCappedByTheApproval() public {
        kshrd.mint(USER, 10e18);
        vm.prank(USER);
        kshrd.approve(address(treasury), 4e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(treasury), 4e18, 5e18
            )
        );
        vm.prank(USER);
        treasury.redeem(5e18, true);

        vm.prank(USER);
        assertEq(treasury.redeem(4e18, true), 4_000_000, "the approved slice redeems normally");
        assertEq(kshrd.allowance(USER, address(treasury)), 0);
    }

    function test_redeem_revertsIfTreasuryLacksBurnerRole() public {
        Treasury orphan = new Treasury(address(usdc), address(kdex), address(kshrd), OWNER);
        usdc.mint(address(orphan), USDC_FLOAT);
        _giveShards(USER, 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(orphan), BURNER_ROLE
            )
        );
        vm.prank(USER);
        orphan.redeem(1e18, true);
    }

    /*//////////////////////////////////////////////////////////////
                              RECOVER TOKEN
    //////////////////////////////////////////////////////////////*/

    function test_recoverToken_movesStrayTokensAndEmits() public {
        MockERC20 stray = new MockERC20("Stray", "STRAY", 18);
        stray.mint(address(treasury), 77e18);

        vm.expectEmit(true, true, false, true, address(treasury));
        emit TokenRecovered(address(stray), USER, 77e18);
        vm.prank(OWNER);
        treasury.recoverToken(address(stray), USER, 77e18);

        assertEq(stray.balanceOf(USER), 77e18);
        assertEq(stray.balanceOf(address(treasury)), 0);
    }

    function test_recoverToken_cannotTouchBackingAssets() public {
        vm.startPrank(OWNER);
        vm.expectRevert("TREAS: backing asset");
        treasury.recoverToken(address(usdc), OWNER, 1);
        vm.expectRevert("TREAS: backing asset");
        treasury.recoverToken(address(kdex), OWNER, 1);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(treasury)), USDC_FLOAT);
        assertEq(kdex.balanceOf(address(treasury)), KDEX_FLOAT);
    }

    function test_recoverToken_revertsOnZeroRecipient() public {
        MockERC20 stray = new MockERC20("Stray", "STRAY", 18);
        stray.mint(address(treasury), 1e18);
        vm.expectRevert("TREAS: zero recipient");
        vm.prank(OWNER);
        treasury.recoverToken(address(stray), address(0), 1e18);
    }

    function test_recoverToken_revertsForNonOwner() public {
        MockERC20 stray = new MockERC20("Stray", "STRAY", 18);
        stray.mint(address(treasury), 1e18);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, STRANGER));
        vm.prank(STRANGER);
        treasury.recoverToken(address(stray), STRANGER, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                                FINDINGS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice REGRESSION (was MEDIUM, ops): `renounceOwnership()` used to be
     *         reachable, and one call stranded every stray token in the Treasury
     *         forever by making `recoverToken` uncallable. It now reverts for
     *         everyone, including the owner.
     */
    function test_renounceOwnershipIsDisabled() public {
        MockERC20 stray = new MockERC20("Stray", "STRAY", 18);
        stray.mint(address(treasury), 1e18);

        vm.expectRevert("TREAS: renounce disabled");
        vm.prank(OWNER);
        treasury.renounceOwnership();

        vm.expectRevert("TREAS: renounce disabled");
        vm.prank(STRANGER);
        treasury.renounceOwnership();

        assertEq(treasury.owner(), OWNER, "ownership is intact");
        vm.prank(OWNER);
        treasury.recoverToken(address(stray), OWNER, 1e18);
        assertEq(stray.balanceOf(OWNER), 1e18, "recovery still works");
    }

    /// @notice Disabling renounce must not disable handover.
    function test_transferOwnershipStillWorks() public {
        MockERC20 stray = new MockERC20("Stray", "STRAY", 18);
        stray.mint(address(treasury), 1e18);

        vm.prank(OWNER);
        treasury.transferOwnership(STRANGER);
        assertEq(treasury.owner(), STRANGER);

        vm.prank(STRANGER);
        treasury.recoverToken(address(stray), STRANGER, 1e18);
        assertEq(stray.balanceOf(STRANGER), 1e18);

        // ...and the new owner cannot renounce either.
        vm.expectRevert("TREAS: renounce disabled");
        vm.prank(STRANGER);
        treasury.renounceOwnership();
    }

    /**
     * @notice FINDING (INFO): the two redemption paths fail differently on an
     *         absurd amount. USDC gives a clean require string; KDEX panics on
     *         `kshrdAmount * 1000` before any check can run.
     */
    function test_FINDING_kdexPathPanicsOnAbsurdAmountWhileUsdcPathRevertsCleanly() public {
        _giveShards(USER, 1e18);

        vm.expectRevert("TREAS: insufficient USDC");
        vm.prank(USER);
        treasury.redeem(type(uint256).max, true);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(USER);
        treasury.redeem(type(uint256).max, false);
    }

    function test_rejectsEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(treasury).call{value: 1 ether}("");
        assertFalse(ok, "Treasury has no receive() - ETH cannot be stranded in it");
        (ok,) = address(treasury).call{value: 1 wei}(abi.encodeWithSignature("usdcScale()"));
        assertFalse(ok);
        (ok,) = address(treasury).call(abi.encodeWithSignature("usdcScale()"));
        assertTrue(ok, "control: same call without ETH succeeds");
    }
}
