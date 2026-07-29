// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";

/// @dev Test-only stand-ins for the real Uniswap v3 deployment on Robinhood
/// Chain, so the unit suite can exercise LaunchVault.finalize() end-to-end
/// without a live fork. The fork test suite is what proves this against the
/// real contracts.
contract MockWETH9 is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "withdraw failed");
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract MockUniswapV3Factory {
    mapping(bytes32 => address) public pools;

    function _key(address a, address b, uint24 fee) internal pure returns (bytes32) {
        (address t0, address t1) = a < b ? (a, b) : (b, a);
        return keccak256(abi.encodePacked(t0, t1, fee));
    }

    function getPool(address a, address b, uint24 fee) external view returns (address) {
        return pools[_key(a, b, fee)];
    }

    function setPool(address a, address b, uint24 fee, address pool) external {
        pools[_key(a, b, fee)] = pool;
    }
}

contract MockPool {
    address public token0;
    address public token1;
    uint24 public fee;
    uint160 public sqrtPriceX96;

    constructor(address token0_, address token1_, uint24 fee_) {
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
    }

    function initialize(uint160 sqrtPriceX96_) external {
        sqrtPriceX96 = sqrtPriceX96_;
    }
}

contract MockPositionManager is ERC721 {
    using SafeERC20 for IERC20;

    MockUniswapV3Factory public immutable factory;
    uint256 public nextId = 1;

    constructor(address factory_) ERC721("Mock LP Position", "MLP") {
        factory = MockUniswapV3Factory(factory_);
    }

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool)
    {
        pool = factory.getPool(token0, token1, fee);
        if (pool == address(0)) {
            MockPool p = new MockPool(token0, token1, fee);
            p.initialize(sqrtPriceX96);
            pool = address(p);
            factory.setPool(token0, token1, fee, pool);
        }
    }

    function mint(INonfungiblePositionManager.MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        address pool = factory.getPool(params.token0, params.token1, params.fee);
        IERC20(params.token0).safeTransferFrom(msg.sender, pool, params.amount0Desired);
        IERC20(params.token1).safeTransferFrom(msg.sender, pool, params.amount1Desired);

        tokenId = nextId++;
        _mint(params.recipient, tokenId);

        liquidity = 1e18;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
    }
}
