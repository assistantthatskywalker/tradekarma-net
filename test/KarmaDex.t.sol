// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {KarmaDex} from "../contracts/KarmaDex.sol";

contract KarmaDexTest is Test {
    KarmaDex internal kdex;

    address internal constant TREASURY = address(0x7EA5);
    address internal constant USER = address(0xCAFE);

    uint256 internal constant SUPPLY = 100_000_000e18;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        kdex = new KarmaDex(SUPPLY, TREASURY);
    }

    function test_constructor_metadataAndFixedSupply() public view {
        assertEq(kdex.name(), "KarmaDex");
        assertEq(kdex.symbol(), "KDEX");
        assertEq(kdex.decimals(), 18);
        assertEq(kdex.totalSupply(), SUPPLY);
        assertEq(kdex.balanceOf(TREASURY), SUPPLY, "entire supply goes to the treasury for distribution");
    }

    function test_constructor_emitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), TREASURY, SUPPLY);
        new KarmaDex(SUPPLY, TREASURY);
    }

    function test_constructor_revertsOnZeroTreasury() public {
        vm.expectRevert("KDEX: zero treasury");
        new KarmaDex(SUPPLY, address(0));
    }

    /// @notice Supply is immutable forever: there is no mint, no owner, no
    ///         admin role, and no fallback that could add one.
    function test_noMintPathExistsAfterConstruction() public {
        (bool ok,) = address(kdex).call(abi.encodeWithSignature("mint(address,uint256)", USER, 1e18));
        assertFalse(ok);
        (ok,) = address(kdex).call(abi.encodeWithSignature("mintEarned(address,uint256,bytes32)", USER, 1e18, bytes32(0)));
        assertFalse(ok);
        (ok,) = address(kdex).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "KDEX must be ownerless");
        (ok,) = address(kdex).call(abi.encodeWithSignature("burn(uint256)", 1e18));
        assertFalse(ok);
        assertEq(kdex.totalSupply(), SUPPLY);
    }

    function test_rejectsEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(kdex).call{value: 1 ether}("");
        assertFalse(ok);
        (ok,) = address(kdex).call{value: 1 wei}(abi.encodeWithSignature("totalSupply()"));
        assertFalse(ok);
        (ok,) = address(kdex).call(abi.encodeWithSignature("totalSupply()"));
        assertTrue(ok, "control: same call without ETH succeeds");
    }

    function test_transfer() public {
        vm.prank(TREASURY);
        assertTrue(kdex.transfer(USER, 1_000e18));
        assertEq(kdex.balanceOf(USER), 1_000e18);
        assertEq(kdex.balanceOf(TREASURY), SUPPLY - 1_000e18);
        assertEq(kdex.totalSupply(), SUPPLY, "transfers never change supply");
    }

    function test_transferFrom_revertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1e18));
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        kdex.transferFrom(TREASURY, USER, 1e18);
    }

    function testFuzz_supplyIsConservedAcrossTransfers(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(TREASURY);
        assertTrue(kdex.transfer(USER, amount));
        assertEq(kdex.balanceOf(TREASURY) + kdex.balanceOf(USER), SUPPLY);
        assertEq(kdex.totalSupply(), SUPPLY);
    }

    function testFuzz_constructorMintsExactlyTheRequestedSupply(uint256 supply, address treasury) public {
        vm.assume(treasury != address(0));
        KarmaDex t = new KarmaDex(supply, treasury);
        assertEq(t.totalSupply(), supply);
        assertEq(t.balanceOf(treasury), supply);
    }
}
