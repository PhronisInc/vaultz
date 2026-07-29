// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Minimal interface, vendored locally instead of importing the full
/// Uniswap v3-core repo (pinned to solc 0.7.6, which would conflict with
/// this project's 0.8.x contracts if compiled together).
interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}
