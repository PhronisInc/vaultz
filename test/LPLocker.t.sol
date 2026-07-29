// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LPLocker} from "../src/LPLocker.sol";
import {MockUniswapV3Factory, MockPositionManager} from "./mocks/MockUniswap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {INonfungiblePositionManager} from "../src/interfaces/INonfungiblePositionManager.sol";

contract DummyToken is ERC20 {
    constructor() ERC20("Dummy", "DUM") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract LPLockerTest is Test {
    MockUniswapV3Factory internal uniFactory;
    MockPositionManager internal pm;
    DummyToken internal tokenA;
    DummyToken internal tokenB;
    address internal beneficiary = makeAddr("beneficiary");
    uint256 internal tokenId;
    LPLocker internal locker;
    uint256 internal unlockTime;

    function setUp() public {
        uniFactory = new MockUniswapV3Factory();
        pm = new MockPositionManager(address(uniFactory));
        tokenA = new DummyToken();
        tokenB = new DummyToken();

        (address t0, address t1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));
        pm.createAndInitializePoolIfNecessary(t0, t1, 3000, 2 ** 96);

        tokenA.approve(address(pm), type(uint256).max);
        tokenB.approve(address(pm), type(uint256).max);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: t0,
            token1: t1,
            fee: 3000,
            tickLower: -60,
            tickUpper: 60,
            amount0Desired: 100 ether,
            amount1Desired: 100 ether,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });
        (tokenId,,,) = pm.mint(params);

        unlockTime = block.timestamp + 180 days;
        locker = new LPLocker(address(pm), tokenId, beneficiary, unlockTime);
        pm.safeTransferFrom(address(this), address(locker), tokenId);
    }

    function test_revert_withdrawBeforeUnlock() public {
        vm.prank(beneficiary);
        vm.expectRevert(LPLocker.NotYetUnlocked.selector);
        locker.withdraw();
    }

    function test_revert_withdrawByNonBeneficiary() public {
        vm.warp(unlockTime);
        vm.expectRevert(LPLocker.NotBeneficiary.selector);
        locker.withdraw();
    }

    function test_withdraw_afterUnlockTransfersNFT() public {
        vm.warp(unlockTime);
        vm.prank(beneficiary);
        locker.withdraw();
        assertEq(pm.ownerOf(tokenId), beneficiary);
    }

    function test_revert_doubleWithdraw() public {
        vm.warp(unlockTime);
        vm.prank(beneficiary);
        locker.withdraw();

        vm.prank(beneficiary);
        vm.expectRevert(LPLocker.AlreadyWithdrawn.selector);
        locker.withdraw();
    }
}
