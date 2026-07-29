// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./helpers/TestBase.t.sol";
import {LaunchVault} from "../src/LaunchVault.sol";
import {VaultToken} from "../src/VaultToken.sol";

contract AntiSnipeTest is TestBase {
    LaunchVault internal vault;
    VaultToken internal token;
    bytes32[] internal emptyProof;
    address internal pool;
    address internal dave = makeAddr("dave");

    function setUp() public override {
        super.setUp();
        (vault, token) = createDefaultLaunch(singleLeafRoot(alice));

        vm.warp(vault.publicStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 20 ether}(emptyProof);
        vm.prank(bob);
        vault.contribute{value: 20 ether}(emptyProof);
        vm.prank(carol);
        vault.contribute{value: 20 ether}(emptyProof);

        vm.warp(vault.deadline());
        vault.finalize();
        pool = token.uniswapPool();
    }

    // ---------------------------------------------------------------------
    // Pre-launch restriction (token-level, before any finalize())
    // ---------------------------------------------------------------------

    function test_preLaunch_onlyVaultCanMoveTokens() public {
        (, VaultToken freshToken) = createDefaultLaunch(singleLeafRoot(alice));

        vm.expectRevert(VaultToken.TradingNotEnabled.selector);
        freshToken.transfer(bob, 0);
    }

    function test_preLaunch_vaultCanMoveTokens() public {
        (LaunchVault freshVault, VaultToken freshToken) = createDefaultLaunch(singleLeafRoot(alice));
        vm.prank(address(freshVault));
        freshToken.transfer(bob, 100 ether);
        assertEq(freshToken.balanceOf(bob), 100 ether);
    }

    function test_revert_onlyVaultCanEnableTrading() public {
        (, VaultToken freshToken) = createDefaultLaunch(singleLeafRoot(alice));
        vm.expectRevert(VaultToken.NotVault.selector);
        freshToken.enableTrading(pool);
    }

    // ---------------------------------------------------------------------
    // Snipe protections after finalize()
    // ---------------------------------------------------------------------

    function test_revert_snipeBlockedInLaunchBlock() public {
        assertEq(block.number, token.launchBlock());
        vm.prank(pool);
        vm.expectRevert(VaultToken.SnipeBlocked.selector);
        token.transfer(dave, 1 ether);
    }

    function test_revert_sellBlockedInLaunchBlockToo() public {
        // vault-originated transfers are always allowed, even pre-window
        vm.prank(address(vault));
        token.transfer(dave, 1 ether);

        // but dave selling into the pool in the exact launch block is still
        // blocked -- the same-block guard covers both buys and sells
        assertEq(block.number, token.launchBlock());
        vm.prank(dave);
        vm.expectRevert(VaultToken.SnipeBlocked.selector);
        token.transfer(pool, 1 ether);
    }

    function test_buyWithinCapSucceeds_duringWindow() public {
        vm.roll(block.number + 1); // one block after launch, still inside the 10-block window
        uint256 cap = token.maxBuyPerWallet();
        vm.prank(pool);
        token.transfer(dave, cap);
        assertEq(token.balanceOf(dave), cap);
    }

    function test_revert_buyExceedsCap_duringWindow() public {
        vm.roll(block.number + 1);
        uint256 cap = token.maxBuyPerWallet();
        vm.prank(pool);
        token.transfer(dave, cap);

        vm.prank(pool);
        vm.expectRevert(VaultToken.MaxBuyExceeded.selector);
        token.transfer(dave, 1);
    }

    function test_capAccumulatesAcrossMultipleBuys_withinWindow() public {
        vm.roll(block.number + 1);
        uint256 cap = token.maxBuyPerWallet();
        vm.prank(pool);
        token.transfer(dave, cap / 2);
        vm.prank(pool);
        token.transfer(dave, cap / 2);

        vm.prank(pool);
        vm.expectRevert(VaultToken.MaxBuyExceeded.selector);
        token.transfer(dave, cap); // pushes cumulative past cap
    }

    function test_buyUnrestricted_afterWindowExpires() public {
        uint256 cap = token.maxBuyPerWallet();
        vm.roll(block.number + token.snipeWindowBlocks() + 1);
        vm.prank(pool);
        token.transfer(dave, cap * 10); // would have far exceeded the cap inside the window
        assertEq(token.balanceOf(dave), cap * 10);
    }

    function test_sellsUnrestricted_duringWindow() public {
        vm.prank(address(vault));
        token.transfer(dave, 1000 ether);
        uint256 poolBalBefore = token.balanceOf(pool);

        vm.roll(block.number + 1);
        vm.prank(dave);
        token.transfer(pool, 1000 ether); // a sell, not a buy — never capped
        assertEq(token.balanceOf(pool), poolBalBefore + 1000 ether);
    }
}
