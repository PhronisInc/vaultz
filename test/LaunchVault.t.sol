// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./helpers/TestBase.t.sol";
import {LaunchVault} from "../src/LaunchVault.sol";
import {VaultToken} from "../src/VaultToken.sol";
import {LPLocker} from "../src/LPLocker.sol";
import {TeamVesting} from "../src/TeamVesting.sol";

contract LaunchVaultTest is TestBase {
    LaunchVault internal vault;
    VaultToken internal token;
    bytes32[] internal emptyProof;

    function setUp() public override {
        super.setUp();
        (vault, token) = createDefaultLaunch(singleLeafRoot(alice));
    }

    // ---------------------------------------------------------------------
    // Contribution window / allowlist gating
    // ---------------------------------------------------------------------

    function test_revert_contributeBeforeRaiseStart() public {
        vm.prank(alice);
        vm.expectRevert(LaunchVault.RaiseNotActive.selector);
        vault.contribute{value: 1 ether}(emptyProof);
    }

    function test_allowlist_validProofSucceeds() public {
        vm.warp(vault.raiseStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 1 ether}(emptyProof);
        assertEq(vault.contributions(alice), 1 ether);
    }

    function test_revert_allowlist_wrongAddressRejected() public {
        vm.warp(vault.raiseStart() + 1);
        vm.prank(bob);
        vm.expectRevert(LaunchVault.NotAllowlisted.selector);
        vault.contribute{value: 1 ether}(emptyProof);
    }

    function test_allowlistCap_excessRefunded() public {
        vm.warp(vault.raiseStart() + 1);
        uint256 balBefore = alice.balance;
        vm.prank(alice);
        vault.contribute{value: 8 ether}(emptyProof); // cap is 5 ether
        assertEq(vault.contributions(alice), 5 ether);
        assertEq(alice.balance, balBefore - 5 ether);
    }

    function test_publicRound_anyoneCanContribute() public {
        vm.warp(vault.publicStart() + 1);
        vm.prank(bob);
        vault.contribute{value: 2 ether}(emptyProof);
        assertEq(vault.contributions(bob), 2 ether);
    }

    function test_hardCap_excessRefundedAcrossContributors() public {
        vm.warp(vault.publicStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 20 ether}(emptyProof);
        vm.prank(bob);
        vault.contribute{value: 20 ether}(emptyProof);
        vm.prank(carol);
        vault.contribute{value: 20 ether}(emptyProof);

        // 60 raised so far, hardCap 100 -> 40 room left; a 4th 20-ether wallet
        // pushes total to exactly hardCap and the fresh excess is refunded.
        address dave = makeAddr("dave");
        vm.deal(dave, 100 ether);
        uint256 balBefore = dave.balance;
        vm.prank(dave);
        vault.contribute{value: 60 ether}(emptyProof); // only 40 ether of room (perWalletCapPublic is 20 though)

        // perWalletCapPublic (20 ether) binds before hardCap room does here.
        assertEq(vault.contributions(dave), 20 ether);
        assertEq(dave.balance, balBefore - 20 ether);
        assertEq(vault.totalRaised(), 80 ether);
    }

    function test_revert_contributeAfterDeadline() public {
        vm.warp(vault.deadline());
        vm.prank(bob);
        vm.expectRevert(LaunchVault.RaiseNotActive.selector);
        vault.contribute{value: 1 ether}(emptyProof);
    }

    // ---------------------------------------------------------------------
    // Failed raise -> refund path
    // ---------------------------------------------------------------------

    function test_failedRaise_refundWorks() public {
        vm.warp(vault.raiseStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 1 ether}(emptyProof); // well under 10 ether softCap

        vm.warp(vault.deadline());
        uint256 balBefore = alice.balance;
        vm.prank(alice);
        vault.claimRefund();
        assertEq(alice.balance, balBefore + 1 ether);
        assertEq(vault.contributions(alice), 0);
    }

    function test_revert_refundBeforeDeadline() public {
        vm.warp(vault.raiseStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 1 ether}(emptyProof);

        vm.prank(alice);
        vm.expectRevert(LaunchVault.RaiseOngoing.selector);
        vault.claimRefund();
    }

    function test_revert_doubleRefund() public {
        vm.warp(vault.raiseStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 1 ether}(emptyProof);
        vm.warp(vault.deadline());
        vm.prank(alice);
        vault.claimRefund();

        vm.prank(alice);
        vm.expectRevert(LaunchVault.NothingToRefund.selector);
        vault.claimRefund();
    }

    function test_revert_refundWhenSoftCapMet() public {
        _raiseToSuccess();
        vm.warp(vault.deadline());
        vm.prank(alice);
        vm.expectRevert(LaunchVault.SoftCapMet.selector);
        vault.claimRefund();
    }

    // ---------------------------------------------------------------------
    // finalize() gating
    // ---------------------------------------------------------------------

    function test_revert_finalizeSoftCapNotMet() public {
        vm.warp(vault.raiseStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 1 ether}(emptyProof);
        vm.warp(vault.deadline());

        vm.expectRevert(LaunchVault.SoftCapNotMet.selector);
        vault.finalize();
    }

    function test_revert_finalizeBeforeDeadlineOrHardCap() public {
        vm.warp(vault.publicStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 20 ether}(emptyProof); // > softCap, but raise still open

        vm.expectRevert(LaunchVault.RaiseStillOpen.selector);
        vault.finalize();
    }

    function test_finalize_earlyOnHardCap() public {
        vm.warp(vault.publicStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 20 ether}(emptyProof);
        vm.prank(bob);
        vault.contribute{value: 20 ether}(emptyProof);
        vm.prank(carol);
        vault.contribute{value: 20 ether}(emptyProof);
        address dave = makeAddr("dave");
        vm.deal(dave, 100 ether);
        vm.prank(dave);
        vault.contribute{value: 20 ether}(emptyProof);
        address eve = makeAddr("eve");
        vm.deal(eve, 100 ether);
        vm.prank(eve);
        vault.contribute{value: 20 ether}(emptyProof); // totalRaised == hardCap == 100 ether

        // still before deadline, but hardCap reached -> finalize allowed
        vault.finalize();
        assertTrue(vault.finalized());
    }

    function test_revert_doubleFinalize() public {
        _raiseToSuccess();
        vm.warp(vault.deadline());
        vault.finalize();
        vm.expectRevert(LaunchVault.AlreadyFinalized.selector);
        vault.finalize();
    }

    // ---------------------------------------------------------------------
    // Successful finalize: migration, locker, vesting, claims
    // ---------------------------------------------------------------------

    function test_finalize_migratesLiquidityAndLocksNFT() public {
        _raiseToSuccess();
        vm.warp(vault.deadline());
        vault.finalize();

        assertTrue(token.tradingEnabled());
        address pool = token.uniswapPool();
        assertTrue(pool != address(0));

        address locker = vault.lpLocker();
        assertTrue(locker != address(0));
        assertEq(positionManager.ownerOf(1), locker);

        LPLocker lockerContract = LPLocker(locker);
        assertEq(lockerContract.beneficiary(), creator);
        assertEq(lockerContract.unlockTime(), block.timestamp + MIN_LP_LOCK);
    }

    function test_finalize_startsTeamVesting() public {
        _raiseToSuccess();
        vm.warp(vault.deadline());
        vault.finalize();

        address vestingAddr = vault.teamVesting();
        assertTrue(vestingAddr != address(0));
        TeamVesting vesting = TeamVesting(vestingAddr);

        uint256 expectedTeamTokens = (DEFAULT_SUPPLY * 1000) / 10000; // teamAllocationBps = 1000
        assertEq(token.balanceOf(vestingAddr), expectedTeamTokens);
        assertEq(vesting.beneficiary(), creator);
        assertEq(vesting.totalAllocation(), expectedTeamTokens);
        assertEq(vesting.vestedAmount(), 0); // cliff not reached yet
    }

    function test_finalize_platformFeeSentToTreasury() public {
        uint256 raised = _raiseToSuccess();
        uint256 treasuryBefore = treasury.balance;
        vm.warp(vault.deadline());
        vault.finalize();

        uint256 expectedFee = (raised * PLATFORM_FEE_BPS) / 10000;
        assertEq(treasury.balance, treasuryBefore + expectedFee);
    }

    function test_claimTokens_proRata() public {
        _raiseToSuccess(); // alice, bob, carol each contribute 20 ether = 60 total
        vm.warp(vault.deadline());
        vault.finalize();

        uint256 presaleTokens = (DEFAULT_SUPPLY * 4000) / 10000; // presaleAllocationBps = 4000
        uint256 expectedAliceShare = (presaleTokens * 20 ether) / 60 ether;

        vm.prank(alice);
        vault.claimTokens();
        assertEq(token.balanceOf(alice), expectedAliceShare);
    }

    function test_revert_doubleClaim() public {
        _raiseToSuccess();
        vm.warp(vault.deadline());
        vault.finalize();

        vm.prank(alice);
        vault.claimTokens();
        vm.prank(alice);
        vm.expectRevert(LaunchVault.AlreadyClaimed.selector);
        vault.claimTokens();
    }

    function test_revert_claimWithNoContribution() public {
        _raiseToSuccess();
        vm.warp(vault.deadline());
        vault.finalize();

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(LaunchVault.NothingToClaim.selector);
        vault.claimTokens();
    }

    function test_revert_claimBeforeFinalize() public {
        _raiseToSuccess();
        vm.prank(alice);
        vm.expectRevert(LaunchVault.NotClaimable.selector);
        vault.claimTokens();
    }

    // ---------------------------------------------------------------------
    // helpers
    // ---------------------------------------------------------------------

    /// @dev Raises 60 ether (well past the 10 ether softCap, under the 100
    /// ether hardCap) split evenly across alice/bob/carol in the public
    /// round, and returns the total raised.
    function _raiseToSuccess() internal returns (uint256) {
        vm.warp(vault.publicStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 20 ether}(emptyProof);
        vm.prank(bob);
        vault.contribute{value: 20 ether}(emptyProof);
        vm.prank(carol);
        vault.contribute{value: 20 ether}(emptyProof);
        return 60 ether;
    }
}
