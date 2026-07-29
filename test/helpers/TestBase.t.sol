// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {LaunchVault} from "../../src/LaunchVault.sol";
import {VaultToken} from "../../src/VaultToken.sol";
import {MockWETH9, MockUniswapV3Factory, MockPositionManager} from "../mocks/MockUniswap.sol";

contract TestBase is Test {
    MockWETH9 internal weth;
    MockUniswapV3Factory internal uniFactory;
    MockPositionManager internal positionManager;
    VaultFactory internal factory;

    address internal treasury = makeAddr("treasury");
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant DEFAULT_SUPPLY = 1_000_000 ether;
    uint256 internal constant MIN_LP_LOCK = 180 days;
    uint256 internal constant MIN_VESTING = 30 days;
    uint256 internal constant MAX_VESTING = 730 days;
    uint256 internal constant PLATFORM_FEE_BPS = 150; // 1.5%

    function setUp() public virtual {
        weth = new MockWETH9();
        uniFactory = new MockUniswapV3Factory();
        positionManager = new MockPositionManager(address(uniFactory));

        factory = new VaultFactory(
            treasury,
            PLATFORM_FEE_BPS,
            MIN_LP_LOCK,
            MIN_VESTING,
            MAX_VESTING,
            address(positionManager),
            address(uniFactory),
            address(weth)
        );

        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(carol, 1000 ether);
    }

    function defaultParams(bytes32 allowlistRoot) internal view returns (VaultFactory.CreateParams memory p) {
        p = VaultFactory.CreateParams({
            name: "Test Token",
            symbol: "TEST",
            totalSupply: DEFAULT_SUPPLY,
            softCap: 10 ether,
            hardCap: 100 ether,
            raiseStart: uint64(block.timestamp + 1 hours),
            publicStart: uint64(block.timestamp + 1 days),
            deadline: uint64(block.timestamp + 2 days),
            allowlistRoot: allowlistRoot,
            perWalletCapAllowlist: 5 ether,
            perWalletCapPublic: 20 ether,
            presaleAllocationBps: 4000,
            liquidityAllocationBps: 5000,
            teamAllocationBps: 1000,
            lpLockDuration: MIN_LP_LOCK,
            vestingCliff: 30 days,
            vestingDuration: 180 days,
            feeTier: 3000,
            snipeWindowBlocks: 10,
            maxBuyBpsOfLiquidity: 500 // 5% of liquidity allocation per wallet during snipe window
        });
    }

    function createDefaultLaunch(bytes32 allowlistRoot) internal returns (LaunchVault vault, VaultToken token) {
        VaultFactory.CreateParams memory p = defaultParams(allowlistRoot);
        vm.prank(creator);
        (address v, address t) = factory.createLaunch(p);
        vault = LaunchVault(v);
        token = VaultToken(t);
    }

    /// @dev Single-leaf Merkle tree trick: with an empty proof, MerkleProof.verify
    /// checks `leaf == root` directly, so the root for an allowlist of exactly one
    /// address is just that address's leaf hash.
    function singleLeafRoot(address who) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(who));
    }
}
