// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {TeamVesting} from "../src/TeamVesting.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyToken is ERC20 {
    constructor() ERC20("Dummy", "DUM") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract TeamVestingTest is Test {
    DummyToken internal token;
    TeamVesting internal vesting;
    address internal beneficiary = makeAddr("beneficiary");

    uint64 internal start;
    uint64 internal cliff = 30 days;
    uint64 internal duration = 180 days;
    uint256 internal allocation = 100_000 ether;

    function setUp() public {
        token = new DummyToken();
        start = uint64(block.timestamp);
        vesting = new TeamVesting(address(token), beneficiary, start, cliff, duration, allocation);
        token.transfer(address(vesting), allocation);
    }

    function test_nothingVestedBeforeCliff() public {
        vm.warp(start + cliff - 1);
        assertEq(vesting.vestedAmount(), 0);
    }

    function test_partialVestingAtCliff() public {
        vm.warp(start + cliff);
        uint256 expected = (allocation * cliff) / duration;
        assertEq(vesting.vestedAmount(), expected);
    }

    function test_linearBetweenCliffAndDuration() public {
        uint256 elapsed = 90 days;
        vm.warp(start + elapsed);
        uint256 expected = (allocation * elapsed) / duration;
        assertEq(vesting.vestedAmount(), expected);
    }

    function test_fullyVestedAtDuration() public {
        vm.warp(start + duration);
        assertEq(vesting.vestedAmount(), allocation);
    }

    function test_fullyVestedAfterDuration() public {
        vm.warp(start + duration + 365 days);
        assertEq(vesting.vestedAmount(), allocation);
    }

    function test_release_paysOutIncrementally() public {
        vm.warp(start + 90 days);
        uint256 expected = (allocation * 90 days) / duration;
        vesting.release();
        assertEq(token.balanceOf(beneficiary), expected);
        assertEq(vesting.released(), expected);

        vm.warp(start + duration);
        vesting.release();
        assertEq(token.balanceOf(beneficiary), allocation);
    }

    function test_release_isPermissionless() public {
        vm.warp(start + duration);
        vm.prank(makeAddr("randomKeeper"));
        vesting.release();
        assertEq(token.balanceOf(beneficiary), allocation);
    }

    function test_revert_releaseWithNothingVested() public {
        vm.expectRevert(TeamVesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_revert_releaseTwiceInSameMoment() public {
        vm.warp(start + duration);
        vesting.release();
        vm.expectRevert(TeamVesting.NothingToRelease.selector);
        vesting.release();
    }
}
