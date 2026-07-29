// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../src/VaultFactory.sol";

/// @notice Deploys the (immutable, ownerless) VaultFactory.
///
/// Required env vars:
///   PRIVATE_KEY               deployer key
///   TREASURY                  platform fee recipient
///   PLATFORM_FEE_BPS          e.g. 150 for 1.5% (hard-capped at 500 = 5% in the contract)
///   MIN_LP_LOCK_DURATION      seconds, e.g. 15552000 for 180 days
///   MIN_VESTING_DURATION      seconds
///   MAX_VESTING_DURATION      seconds
///   POSITION_MANAGER          Uniswap v3 NonfungiblePositionManager on Robinhood Chain
///   UNISWAP_V3_FACTORY        Uniswap v3 Factory on Robinhood Chain
///   WETH                      wrapped native token on Robinhood Chain
///
/// IMPORTANT: POSITION_MANAGER / UNISWAP_V3_FACTORY / WETH must be pulled
/// fresh from Robinhood Chain's Blockscout explorer or Uniswap's official
/// deployment registry immediately before running this script — do not
/// reuse addresses from a chat, a cached doc, or an old run without
/// re-checking them on-chain. A wrong address here misdirects every future
/// launch's liquidity.
contract DeployFactory is Script {
    function run() external returns (VaultFactory factory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address treasury = vm.envAddress("TREASURY");
        uint256 platformFeeBps = vm.envUint("PLATFORM_FEE_BPS");
        uint256 minLpLockDuration = vm.envUint("MIN_LP_LOCK_DURATION");
        uint256 minVestingDuration = vm.envUint("MIN_VESTING_DURATION");
        uint256 maxVestingDuration = vm.envUint("MAX_VESTING_DURATION");
        address positionManager = vm.envAddress("POSITION_MANAGER");
        address uniswapV3Factory = vm.envAddress("UNISWAP_V3_FACTORY");
        address weth = vm.envAddress("WETH");

        console.log("Deploying VaultFactory with:");
        console.log("  treasury           ", treasury);
        console.log("  platformFeeBps     ", platformFeeBps);
        console.log("  minLpLockDuration  ", minLpLockDuration);
        console.log("  positionManager    ", positionManager);
        console.log("  uniswapV3Factory   ", uniswapV3Factory);
        console.log("  weth               ", weth);

        vm.startBroadcast(deployerKey);
        factory = new VaultFactory(
            treasury,
            platformFeeBps,
            minLpLockDuration,
            minVestingDuration,
            maxVestingDuration,
            positionManager,
            uniswapV3Factory,
            weth
        );
        vm.stopBroadcast();

        console.log("VaultFactory deployed at:", address(factory));
    }
}
