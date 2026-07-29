// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {VaultToken} from "./VaultToken.sol";
import {LPLocker} from "./LPLocker.sol";
import {TeamVesting} from "./TeamVesting.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";

/// @notice One presale/alpha raise. Runs an allowlist round then a public
/// round, both capped per-wallet; on success, `finalize()` is permissionless
/// and atomically pays the platform fee, mints a full-range Uniswap v3
/// position from the raised ETH + a token allocation, locks that position in
/// a fresh LPLocker, starts the team's vesting, enables trading on the
/// token, and opens pro-rata presale claims. On failure (softcap missed by
/// the deadline), contributors pull their own refund.
contract LaunchVault is ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    error NotFactory();
    error AlreadySet();
    error RaiseNotActive();
    error NotAllowlisted();
    error CapReached();
    error ZeroContribution();
    error RefundTransferFailed();
    error RaiseStillOpen();
    error RaiseOngoing();
    error SoftCapNotMet();
    error SoftCapMet();
    error AlreadyFinalized();
    error NotClaimable();
    error NothingToClaim();
    error AlreadyClaimed();
    error NothingToRefund();
    error UnsupportedFeeTier();

    struct Config {
        address creator;
        address factory;
        uint256 softCap;
        uint256 hardCap;
        uint64 raiseStart;
        uint64 publicStart;
        uint64 deadline;
        bytes32 allowlistRoot;
        uint256 perWalletCapAllowlist;
        uint256 perWalletCapPublic;
        uint256 totalSupply;
        uint16 presaleAllocationBps;
        uint16 liquidityAllocationBps;
        uint16 teamAllocationBps;
        uint256 platformFeeBps;
        address treasury;
        uint256 lpLockDuration;
        uint64 vestingCliff;
        uint64 vestingDuration;
        uint24 feeTier;
        uint256 snipeWindowBlocks;
        address positionManager;
        address uniswapV3Factory;
        address weth;
    }

    address public immutable creator;
    address public immutable factory;
    uint256 public immutable softCap;
    uint256 public immutable hardCap;
    uint64 public immutable raiseStart;
    uint64 public immutable publicStart;
    uint64 public immutable deadline;
    bytes32 public immutable allowlistRoot;
    uint256 public immutable perWalletCapAllowlist;
    uint256 public immutable perWalletCapPublic;
    uint256 public immutable totalSupply;
    uint16 public immutable presaleAllocationBps;
    uint16 public immutable liquidityAllocationBps;
    uint16 public immutable teamAllocationBps;
    uint256 public immutable platformFeeBps;
    address public immutable treasury;
    uint256 public immutable lpLockDuration;
    uint64 public immutable vestingCliff;
    uint64 public immutable vestingDuration;
    uint24 public immutable feeTier;
    uint256 public immutable snipeWindowBlocks;
    INonfungiblePositionManager public immutable positionManager;
    IUniswapV3Factory public immutable uniswapV3Factory;
    address public immutable weth;

    VaultToken public token;

    mapping(address => uint256) public contributions;
    mapping(address => bool) public hasClaimed;
    uint256 public totalRaised;
    bool public finalized;
    bool public presaleClaimable;

    address public lpLocker;
    address public teamVesting;

    event TokenSet(address indexed token);
    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Finalized(address indexed pool, address indexed locker, uint256 lpTokenId, address vesting);
    event Claimed(address indexed contributor, uint256 amount);

    int24 private constant MIN_TICK = -887272;
    int24 private constant MAX_TICK = 887272;

    constructor(Config memory c) {
        creator = c.creator;
        factory = c.factory;
        softCap = c.softCap;
        hardCap = c.hardCap;
        raiseStart = c.raiseStart;
        publicStart = c.publicStart;
        deadline = c.deadline;
        allowlistRoot = c.allowlistRoot;
        perWalletCapAllowlist = c.perWalletCapAllowlist;
        perWalletCapPublic = c.perWalletCapPublic;
        totalSupply = c.totalSupply;
        presaleAllocationBps = c.presaleAllocationBps;
        liquidityAllocationBps = c.liquidityAllocationBps;
        teamAllocationBps = c.teamAllocationBps;
        platformFeeBps = c.platformFeeBps;
        treasury = c.treasury;
        lpLockDuration = c.lpLockDuration;
        vestingCliff = c.vestingCliff;
        vestingDuration = c.vestingDuration;
        feeTier = c.feeTier;
        snipeWindowBlocks = c.snipeWindowBlocks;
        positionManager = INonfungiblePositionManager(c.positionManager);
        uniswapV3Factory = IUniswapV3Factory(c.uniswapV3Factory);
        weth = c.weth;
    }

    /// @dev Called exactly once by the factory, in the same transaction that
    /// deploys this vault, to break the vault/token constructor circular
    /// dependency (the token's constructor needs this vault's address).
    function setToken(address token_) external {
        if (msg.sender != factory) revert NotFactory();
        if (address(token) != address(0)) revert AlreadySet();
        token = VaultToken(token_);
        emit TokenSet(token_);
    }

    function contribute(bytes32[] calldata merkleProof) external payable nonReentrant {
        if (block.timestamp < raiseStart || block.timestamp >= deadline) revert RaiseNotActive();
        if (finalized) revert AlreadyFinalized();
        if (msg.value == 0) revert ZeroContribution();

        uint256 cap;
        if (block.timestamp < publicStart) {
            if (!MerkleProof.verify(merkleProof, allowlistRoot, keccak256(abi.encodePacked(msg.sender)))) {
                revert NotAllowlisted();
            }
            cap = perWalletCapAllowlist;
        } else {
            cap = perWalletCapPublic;
        }

        uint256 already = contributions[msg.sender];
        uint256 walletRoom = cap > already ? cap - already : 0;
        uint256 hardCapRoom = hardCap > totalRaised ? hardCap - totalRaised : 0;

        uint256 accepted = msg.value;
        if (accepted > walletRoom) accepted = walletRoom;
        if (accepted > hardCapRoom) accepted = hardCapRoom;
        if (accepted == 0) revert CapReached();

        contributions[msg.sender] = already + accepted;
        totalRaised += accepted;

        uint256 refund = msg.value - accepted;
        if (refund > 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            if (!ok) revert RefundTransferFailed();
        }

        emit Contributed(msg.sender, accepted);
    }

    function claimRefund() external nonReentrant {
        if (block.timestamp < deadline) revert RaiseOngoing();
        if (totalRaised >= softCap) revert SoftCapMet();
        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NothingToRefund();
        contributions[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert RefundTransferFailed();
        emit Refunded(msg.sender, amount);
    }

    /// @dev Permissionless by design: the outcome is fully determined by
    /// on-chain state (totalRaised vs. softCap/hardCap/deadline), so there is
    /// no meaningful advantage to being the one who calls it.
    function finalize() external nonReentrant {
        if (finalized) revert AlreadyFinalized();
        if (totalRaised < softCap) revert SoftCapNotMet();
        if (block.timestamp < deadline && totalRaised < hardCap) revert RaiseStillOpen();
        finalized = true;

        uint256 fee = (totalRaised * platformFeeBps) / 10000;
        uint256 netETH = totalRaised - fee;
        if (fee > 0) {
            (bool ok,) = treasury.call{value: fee}("");
            if (!ok) revert RefundTransferFailed();
        }

        (address pool, uint256 lpTokenId) = _migrateLiquidity(netETH);

        address vesting = _startTeamVesting();

        presaleClaimable = true;

        emit Finalized(pool, lpLocker, lpTokenId, vesting);
    }

    function claimTokens() external nonReentrant {
        if (!presaleClaimable) revert NotClaimable();
        uint256 contributed = contributions[msg.sender];
        if (contributed == 0) revert NothingToClaim();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();
        hasClaimed[msg.sender] = true;

        uint256 presaleTokens = (totalSupply * presaleAllocationBps) / 10000;
        uint256 share = (presaleTokens * contributed) / totalRaised;
        IERC20(address(token)).safeTransfer(msg.sender, share);

        emit Claimed(msg.sender, share);
    }

    function _migrateLiquidity(uint256 netETH) private returns (address pool, uint256 lpTokenId) {
        uint256 liquidityTokens = (totalSupply * liquidityAllocationBps) / 10000;

        IWETH9(weth).deposit{value: netETH}();

        address tokenAddr = address(token);
        (address token0, address token1, uint256 amount0Desired, uint256 amount1Desired) = tokenAddr < weth
            ? (tokenAddr, weth, liquidityTokens, netETH)
            : (weth, tokenAddr, netETH, liquidityTokens);

        IERC20(tokenAddr).forceApprove(address(positionManager), liquidityTokens);
        IERC20(weth).forceApprove(address(positionManager), netETH);

        uint160 sqrtPriceX96 = _sqrtPriceX96(amount0Desired, amount1Desired);
        positionManager.createAndInitializePoolIfNecessary(token0, token1, feeTier, sqrtPriceX96);

        (int24 tickLower, int24 tickUpper) = _fullRangeTicks(_tickSpacing(feeTier));

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: feeTier,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: (amount0Desired * 9800) / 10000,
            amount1Min: (amount1Desired * 9800) / 10000,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId,,,) = positionManager.mint(params);
        lpTokenId = tokenId;

        pool = uniswapV3Factory.getPool(token0, token1, feeTier);
        token.enableTrading(pool);

        LPLocker locker = new LPLocker(address(positionManager), tokenId, creator, block.timestamp + lpLockDuration);
        lpLocker = address(locker);
        positionManager.safeTransferFrom(address(this), address(locker), tokenId);
    }

    function _startTeamVesting() private returns (address vesting) {
        uint256 teamTokens = (totalSupply * teamAllocationBps) / 10000;
        if (teamTokens == 0) return address(0);

        TeamVesting v = new TeamVesting(
            address(token), creator, uint64(block.timestamp), vestingCliff, vestingDuration, teamTokens
        );
        teamVesting = address(v);
        IERC20(address(token)).safeTransfer(address(v), teamTokens);
        return address(v);
    }

    /// @dev sqrtPriceX96 = sqrt(amount1/amount0) * 2^96, computed via a single
    /// full-precision mulDiv (OZ Math) followed by an integer sqrt, so it
    /// never overflows the way a naive `amount1 * 2^192 / amount0` would for
    /// realistic raise sizes.
    function _sqrtPriceX96(uint256 amount0, uint256 amount1) private pure returns (uint160) {
        uint256 ratioX192 = Math.mulDiv(amount1, 1 << 192, amount0);
        return uint160(Math.sqrt(ratioX192));
    }

    function _tickSpacing(uint24 fee) private pure returns (int24) {
        if (fee == 500) return 10;
        if (fee == 3000) return 60;
        if (fee == 10000) return 200;
        revert UnsupportedFeeTier();
    }

    function _fullRangeTicks(int24 spacing) private pure returns (int24 tickLower, int24 tickUpper) {
        tickLower = (MIN_TICK / spacing) * spacing;
        if (tickLower < MIN_TICK) tickLower += spacing;
        tickUpper = (MAX_TICK / spacing) * spacing;
        if (tickUpper > MAX_TICK) tickUpper -= spacing;
    }
}
