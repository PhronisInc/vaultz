// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Fixed-supply launch token. The entire supply is minted once, to the
/// vault, at construction — there is no mint() function, ever. Before the vault
/// finalizes the raise, only the vault itself may move tokens (funding the LP
/// mint, team vesting, and presale claims); nobody can pre-acquire a tradeable
/// balance. Once trading is enabled, the only remaining restriction is a
/// hardcoded, non-togglable anti-snipe window on transfers touching the
/// Uniswap pool address.
contract VaultToken is ERC20 {
    error TradingNotEnabled();
    error AlreadyEnabled();
    error NotVault();
    error SnipeBlocked();
    error MaxBuyExceeded();

    address public immutable vault;
    uint256 public immutable snipeWindowBlocks;
    uint256 public immutable maxBuyPerWallet;

    address public uniswapPool;
    uint256 public launchBlock;
    bool public tradingEnabled;

    mapping(address => uint256) public poolBuysDuringWindow;

    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address vault_,
        uint256 snipeWindowBlocks_,
        uint256 maxBuyPerWallet_
    ) ERC20(name_, symbol_) {
        vault = vault_;
        snipeWindowBlocks = snipeWindowBlocks_;
        maxBuyPerWallet = maxBuyPerWallet_;
        _mint(vault_, totalSupply_);
    }

    /// @dev Callable exactly once, by the vault, in the same transaction the
    /// Uniswap liquidity position is minted.
    function enableTrading(address pool_) external onlyVault {
        if (tradingEnabled) revert AlreadyEnabled();
        tradingEnabled = true;
        uniswapPool = pool_;
        launchBlock = block.number;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (!tradingEnabled) {
            if (from != address(0) && from != vault) revert TradingNotEnabled();
        } else if (uniswapPool != address(0) && (from == uniswapPool || to == uniswapPool)) {
            if (block.number == launchBlock) revert SnipeBlocked();
            if (block.number < launchBlock + snipeWindowBlocks && to != uniswapPool) {
                uint256 newTotal = poolBuysDuringWindow[to] + value;
                if (newTotal > maxBuyPerWallet) revert MaxBuyExceeded();
                poolBuysDuringWindow[to] = newTotal;
            }
        }
        super._update(from, to, value);
    }
}
