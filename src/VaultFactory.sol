// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchVault} from "./LaunchVault.sol";
import {VaultToken} from "./VaultToken.sol";

/// @notice Permissionless launch factory. Every platform-wide parameter
/// (treasury, fee, minimum LP lock floor, vesting bounds, Uniswap/WETH
/// addresses) is immutable, set once at deployment. There is no owner and no
/// setter anywhere in this contract — changing platform terms means
/// deploying a new VaultFactory, not flipping a knob on this one.
contract VaultFactory {
    error InvalidBps();
    error LockTooShort();
    error InvalidVestingDuration();
    error InvalidVestingParams();
    error InvalidTimestamps();
    error InvalidFeeTier();
    error InvalidCaps();
    error InvalidWalletCaps();
    error FeeTooHigh();

    uint256 public constant MAX_PLATFORM_FEE_BPS = 500; // 5% hard ceiling
    uint16 public constant BPS_DENOMINATOR = 10000;

    address public immutable treasury;
    uint256 public immutable platformFeeBps;
    uint256 public immutable minLpLockDuration;
    uint256 public immutable minVestingDuration;
    uint256 public immutable maxVestingDuration;
    address public immutable positionManager;
    address public immutable uniswapV3Factory;
    address public immutable weth;

    event LaunchCreated(address indexed creator, address indexed vault, address indexed token);

    struct CreateParams {
        string name;
        string symbol;
        uint256 totalSupply;
        uint256 softCap;
        uint256 hardCap;
        uint64 raiseStart;
        uint64 publicStart;
        uint64 deadline;
        bytes32 allowlistRoot;
        uint256 perWalletCapAllowlist;
        uint256 perWalletCapPublic;
        uint16 presaleAllocationBps;
        uint16 liquidityAllocationBps;
        uint16 teamAllocationBps;
        uint256 lpLockDuration;
        uint64 vestingCliff;
        uint64 vestingDuration;
        uint24 feeTier;
        uint256 snipeWindowBlocks;
        uint16 maxBuyBpsOfLiquidity;
    }

    constructor(
        address treasury_,
        uint256 platformFeeBps_,
        uint256 minLpLockDuration_,
        uint256 minVestingDuration_,
        uint256 maxVestingDuration_,
        address positionManager_,
        address uniswapV3Factory_,
        address weth_
    ) {
        if (platformFeeBps_ > MAX_PLATFORM_FEE_BPS) revert FeeTooHigh();
        if (minVestingDuration_ > maxVestingDuration_) revert InvalidVestingDuration();
        treasury = treasury_;
        platformFeeBps = platformFeeBps_;
        minLpLockDuration = minLpLockDuration_;
        minVestingDuration = minVestingDuration_;
        maxVestingDuration = maxVestingDuration_;
        positionManager = positionManager_;
        uniswapV3Factory = uniswapV3Factory_;
        weth = weth_;
    }

    function createLaunch(CreateParams calldata p) external returns (address vault, address token) {
        _validate(p);

        LaunchVault newVault = new LaunchVault(
            LaunchVault.Config({
                creator: msg.sender,
                factory: address(this),
                softCap: p.softCap,
                hardCap: p.hardCap,
                raiseStart: p.raiseStart,
                publicStart: p.publicStart,
                deadline: p.deadline,
                allowlistRoot: p.allowlistRoot,
                perWalletCapAllowlist: p.perWalletCapAllowlist,
                perWalletCapPublic: p.perWalletCapPublic,
                totalSupply: p.totalSupply,
                presaleAllocationBps: p.presaleAllocationBps,
                liquidityAllocationBps: p.liquidityAllocationBps,
                teamAllocationBps: p.teamAllocationBps,
                platformFeeBps: platformFeeBps,
                treasury: treasury,
                lpLockDuration: p.lpLockDuration,
                vestingCliff: p.vestingCliff,
                vestingDuration: p.vestingDuration,
                feeTier: p.feeTier,
                snipeWindowBlocks: p.snipeWindowBlocks,
                positionManager: positionManager,
                uniswapV3Factory: uniswapV3Factory,
                weth: weth
            })
        );

        uint256 liquidityTokens = (p.totalSupply * p.liquidityAllocationBps) / BPS_DENOMINATOR;
        uint256 maxBuyPerWallet = (liquidityTokens * p.maxBuyBpsOfLiquidity) / BPS_DENOMINATOR;

        VaultToken newToken =
            new VaultToken(p.name, p.symbol, p.totalSupply, address(newVault), p.snipeWindowBlocks, maxBuyPerWallet);

        newVault.setToken(address(newToken));

        emit LaunchCreated(msg.sender, address(newVault), address(newToken));
        return (address(newVault), address(newToken));
    }

    function _validate(CreateParams calldata p) private view {
        if (uint256(p.presaleAllocationBps) + p.liquidityAllocationBps + p.teamAllocationBps != BPS_DENOMINATOR) {
            revert InvalidBps();
        }
        if (p.lpLockDuration < minLpLockDuration) revert LockTooShort();
        if (p.vestingDuration < minVestingDuration || p.vestingDuration > maxVestingDuration) {
            revert InvalidVestingDuration();
        }
        if (p.vestingCliff > p.vestingDuration) revert InvalidVestingParams();
        if (!(p.raiseStart < p.publicStart && p.publicStart < p.deadline)) revert InvalidTimestamps();
        if (p.feeTier != 500 && p.feeTier != 3000 && p.feeTier != 10000) revert InvalidFeeTier();
        if (p.softCap == 0 || p.hardCap < p.softCap) revert InvalidCaps();
        if (p.perWalletCapAllowlist == 0 || p.perWalletCapPublic == 0) revert InvalidWalletCaps();
        if (p.maxBuyBpsOfLiquidity == 0 || p.maxBuyBpsOfLiquidity > BPS_DENOMINATOR) revert InvalidBps();
    }
}
