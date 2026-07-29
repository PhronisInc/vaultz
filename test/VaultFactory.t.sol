// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./helpers/TestBase.t.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {LaunchVault} from "../src/LaunchVault.sol";
import {VaultToken} from "../src/VaultToken.sol";

contract VaultFactoryTest is TestBase {
    function test_createLaunch_wiresVaultAndToken() public {
        (LaunchVault vault, VaultToken token) = createDefaultLaunch(singleLeafRoot(alice));

        assertEq(address(vault.token()), address(token));
        assertEq(token.vault(), address(vault));
        assertEq(token.totalSupply(), DEFAULT_SUPPLY);
        assertEq(token.balanceOf(address(vault)), DEFAULT_SUPPLY);
        assertEq(vault.creator(), creator);
        assertEq(vault.factory(), address(factory));
    }

    function test_createLaunch_emitsEvent() public {
        VaultFactory.CreateParams memory p = defaultParams(singleLeafRoot(alice));
        vm.expectEmit(false, false, false, false);
        emit VaultFactory.LaunchCreated(creator, address(0), address(0));
        vm.prank(creator);
        factory.createLaunch(p);
    }

    function test_revert_bpsMustSumTo10000() public {
        VaultFactory.CreateParams memory p = defaultParams(singleLeafRoot(alice));
        p.teamAllocationBps = 2000; // now sums to 11000
        vm.expectRevert(VaultFactory.InvalidBps.selector);
        factory.createLaunch(p);
    }

    function test_revert_lockBelowFloor() public {
        VaultFactory.CreateParams memory p = defaultParams(singleLeafRoot(alice));
        p.lpLockDuration = MIN_LP_LOCK - 1;
        vm.expectRevert(VaultFactory.LockTooShort.selector);
        factory.createLaunch(p);
    }

    function test_revert_vestingDurationOutOfBounds() public {
        VaultFactory.CreateParams memory p = defaultParams(singleLeafRoot(alice));
        p.vestingDuration = uint64(MIN_VESTING - 1);
        vm.expectRevert(VaultFactory.InvalidVestingDuration.selector);
        factory.createLaunch(p);
    }

    function test_revert_cliffLongerThanDuration() public {
        VaultFactory.CreateParams memory p = defaultParams(singleLeafRoot(alice));
        p.vestingCliff = p.vestingDuration + 1;
        vm.expectRevert(VaultFactory.InvalidVestingParams.selector);
        factory.createLaunch(p);
    }

    function test_revert_badTimestampOrdering() public {
        VaultFactory.CreateParams memory p = defaultParams(singleLeafRoot(alice));
        p.publicStart = p.raiseStart - 1;
        vm.expectRevert(VaultFactory.InvalidTimestamps.selector);
        factory.createLaunch(p);
    }

    function test_revert_unsupportedFeeTier() public {
        VaultFactory.CreateParams memory p = defaultParams(singleLeafRoot(alice));
        p.feeTier = 1234;
        vm.expectRevert(VaultFactory.InvalidFeeTier.selector);
        factory.createLaunch(p);
    }

    function test_revert_hardCapBelowSoftCap() public {
        VaultFactory.CreateParams memory p = defaultParams(singleLeafRoot(alice));
        p.hardCap = p.softCap - 1;
        vm.expectRevert(VaultFactory.InvalidCaps.selector);
        factory.createLaunch(p);
    }

    function test_revert_zeroWalletCap() public {
        VaultFactory.CreateParams memory p = defaultParams(singleLeafRoot(alice));
        p.perWalletCapPublic = 0;
        vm.expectRevert(VaultFactory.InvalidWalletCaps.selector);
        factory.createLaunch(p);
    }

    function test_revert_feeTooHighAtDeploy() public {
        vm.expectRevert(VaultFactory.FeeTooHigh.selector);
        new VaultFactory(
            treasury, 501, MIN_LP_LOCK, MIN_VESTING, MAX_VESTING, address(positionManager), address(uniFactory), address(weth)
        );
    }
}
