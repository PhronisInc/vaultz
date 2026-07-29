// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {VaultFactory} from "../src/VaultFactory.sol";

/// @notice Creates a single throwaway launch with short windows against an
/// already-deployed VaultFactory, for a manual end-to-end dry run on
/// Robinhood Chain testnet. This script only creates the launch; contribute
/// past the allowlist/public windows and finalize afterward with `cast send`
/// (commands are printed at the end) so you can watch each phase happen for
/// real rather than scripting the whole lifecycle blind.
///
/// Required env vars:
///   PRIVATE_KEY       deployer/creator key (also becomes the sole allowlisted
///                      address for this demo, via the single-leaf Merkle trick)
///   FACTORY_ADDRESS    address of a VaultFactory already deployed via DeployFactory.s.sol
contract DemoLaunch is Script {
    function run() external returns (address vault, address token) {
        uint256 creatorKey = vm.envUint("PRIVATE_KEY");
        address creator = vm.addr(creatorKey);
        VaultFactory factory = VaultFactory(vm.envAddress("FACTORY_ADDRESS"));

        uint64 raiseStart = uint64(block.timestamp + 2 minutes);
        uint64 publicStart = uint64(block.timestamp + 7 minutes);
        uint64 deadline = uint64(block.timestamp + 12 minutes);

        VaultFactory.CreateParams memory p = VaultFactory.CreateParams({
            name: "Vaultz Demo Token",
            symbol: "VDEMO",
            totalSupply: 1_000_000 ether,
            softCap: 0.01 ether,
            hardCap: 0.1 ether,
            raiseStart: raiseStart,
            publicStart: publicStart,
            deadline: deadline,
            allowlistRoot: keccak256(abi.encodePacked(creator)),
            perWalletCapAllowlist: 0.05 ether,
            perWalletCapPublic: 0.05 ether,
            presaleAllocationBps: 4000,
            liquidityAllocationBps: 5000,
            teamAllocationBps: 1000,
            lpLockDuration: factory.minLpLockDuration(),
            vestingCliff: uint64(factory.minVestingDuration() / 6),
            vestingDuration: uint64(factory.minVestingDuration()),
            feeTier: 3000,
            snipeWindowBlocks: 10,
            maxBuyBpsOfLiquidity: 500
        });

        vm.startBroadcast(creatorKey);
        (vault, token) = factory.createLaunch(p);
        vm.stopBroadcast();

        console.log("Vault  :", vault);
        console.log("Token  :", token);
        console.log("");
        console.log("Next steps (replace $RPC / $PRIVATE_KEY as needed):");
        console.log("  1. Wait until raiseStart, then contribute (empty proof array [] works: you are the only allowlisted address):");
        console.log(
            string.concat(
                "     cast send ", _toHex(vault), ' "contribute(bytes32[])" "[]" --value 0.01ether --private-key $PRIVATE_KEY --rpc-url $RPC'
            )
        );
        console.log("  2. Wait until deadline (or hardCap is hit), then finalize (anyone may call this):");
        console.log(string.concat("     cast send ", _toHex(vault), ' "finalize()" --private-key $PRIVATE_KEY --rpc-url $RPC'));
        console.log("  3. Claim your presale allocation:");
        console.log(string.concat("     cast send ", _toHex(vault), ' "claimTokens()" --private-key $PRIVATE_KEY --rpc-url $RPC'));
        console.log("  4. Confirm a real pool now exists and the position NFT sits in the printed LPLocker:");
        console.log(string.concat("     cast call ", _toHex(vault), ' "lpLocker()(address)" --rpc-url $RPC'));
    }

    function _toHex(address a) private pure returns (string memory) {
        return vm.toString(a);
    }
}
