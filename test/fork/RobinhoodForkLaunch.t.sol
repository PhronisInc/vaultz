// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {LaunchVault} from "../../src/LaunchVault.sol";
import {VaultToken} from "../../src/VaultToken.sol";
import {LPLocker} from "../../src/LPLocker.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Full lifecycle against the REAL Uniswap v3 deployment on
/// Robinhood Chain mainnet (forked, no funds actually leave the fork).
/// Addresses below were independently verified on-chain (see .env.example)
/// on 2026-07-29 -- re-verify before relying on this again months later.
///
/// Run with: forge test --match-path test/fork/RobinhoodForkLaunch.t.sol --fork-url https://rpc.mainnet.chain.robinhood.com -vvv
contract RobinhoodForkLaunchTest is Test {
    address internal constant POSITION_MANAGER = 0x73991a25C818Bf1f1128dEAaB1492D45638DE0D3;
    address internal constant UNISWAP_V3_FACTORY = 0x1f7d7550B1b028f7571E69A784071F0205FD2EfA;
    address internal constant WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;

    VaultFactory internal factory;
    address internal treasury = makeAddr("treasury");
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        string memory rpc = vm.envOr("RH_MAINNET_RPC", string("https://rpc.mainnet.chain.robinhood.com"));
        vm.createSelectFork(rpc);
        require(block.chainid == 4663, "not forked from Robinhood Chain mainnet");

        factory = new VaultFactory(
            treasury, 150, 180 days, 30 days, 730 days, POSITION_MANAGER, UNISWAP_V3_FACTORY, WETH
        );

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function test_fork_fullLaunchLifecycleAgainstRealUniswap() public {
        VaultFactory.CreateParams memory p = VaultFactory.CreateParams({
            name: "Fork Test Token",
            symbol: "FORK",
            totalSupply: 1_000_000 ether,
            softCap: 5 ether,
            hardCap: 40 ether,
            raiseStart: uint64(block.timestamp + 1 hours),
            publicStart: uint64(block.timestamp + 1 days),
            deadline: uint64(block.timestamp + 2 days),
            allowlistRoot: keccak256(abi.encodePacked(alice)),
            perWalletCapAllowlist: 5 ether,
            perWalletCapPublic: 20 ether,
            presaleAllocationBps: 4000,
            liquidityAllocationBps: 5000,
            teamAllocationBps: 1000,
            lpLockDuration: 180 days,
            vestingCliff: 30 days,
            vestingDuration: 180 days,
            feeTier: 3000,
            snipeWindowBlocks: 10,
            maxBuyBpsOfLiquidity: 500
        });

        vm.prank(creator);
        (address vaultAddr, address tokenAddr) = factory.createLaunch(p);
        LaunchVault vault = LaunchVault(vaultAddr);
        VaultToken token = VaultToken(tokenAddr);

        bytes32[] memory emptyProof = new bytes32[](0);

        vm.warp(vault.publicStart() + 1);
        vm.prank(alice);
        vault.contribute{value: 20 ether}(emptyProof);
        vm.prank(bob);
        vault.contribute{value: 20 ether}(emptyProof);

        vm.warp(vault.deadline());
        vault.finalize();

        assertTrue(token.tradingEnabled(), "trading should be enabled after finalize");
        address pool = token.uniswapPool();
        assertTrue(pool != address(0), "real Uniswap pool should exist");
        assertTrue(pool.code.length > 0, "pool must have real bytecode");

        address locker = vault.lpLocker();
        assertTrue(locker != address(0));
        uint256 lockedTokenId = LPLocker(locker).tokenId();
        assertEq(IERC721(POSITION_MANAGER).ownerOf(lockedTokenId), locker, "real NFPM must show locker as owner");

        vm.prank(alice);
        vault.claimTokens();
        assertTrue(token.balanceOf(alice) > 0, "alice should have claimed a presale share");

        assertTrue(vault.teamVesting() != address(0));
    }
}
