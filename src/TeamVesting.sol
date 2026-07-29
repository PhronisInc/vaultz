// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Linear vesting with an optional cliff for one launch's team
/// allocation. Deliberately has no revoke/claw-back function — once deployed
/// and funded, the schedule is a promise the platform itself cannot break.
contract TeamVesting {
    using SafeERC20 for IERC20;

    error NothingToRelease();

    IERC20 public immutable token;
    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable cliff;
    uint64 public immutable duration;
    uint256 public immutable totalAllocation;
    uint256 public released;

    constructor(
        address token_,
        address beneficiary_,
        uint64 start_,
        uint64 cliff_,
        uint64 duration_,
        uint256 totalAllocation_
    ) {
        token = IERC20(token_);
        beneficiary = beneficiary_;
        start = start_;
        cliff = cliff_;
        duration = duration_;
        totalAllocation = totalAllocation_;
    }

    function vestedAmount() public view returns (uint256) {
        if (block.timestamp < start + cliff) return 0;
        if (block.timestamp >= start + duration) return totalAllocation;
        return (totalAllocation * (block.timestamp - start)) / duration;
    }

    function releasable() public view returns (uint256) {
        return vestedAmount() - released;
    }

    /// @dev Permissionless — always pays out to the fixed `beneficiary`
    /// regardless of caller, so anyone (e.g. a keeper) may trigger it.
    function release() external {
        uint256 amount = releasable();
        if (amount == 0) revert NothingToRelease();
        released += amount;
        token.safeTransfer(beneficiary, amount);
    }
}
