// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseHook} from "@uniswap/v4-periphery/contracts/BaseHook.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/contracts/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";

interface IBurnEngine {
    function recordVolatility(uint256 volatilityBps) external;
}

/**
 * @title NULLAIHooks
 * @author NULLAI Core Team
 * @notice Uniswap V4 Hook integrated with the NULLAI Dynamic Burn Engine.
 *
 * EIP-1153 transient slots used:
 *   1. PRE_SWAP_PRICE_SLOT  — sqrtPriceX96 captured in beforeSwap
 *   2. VOLATILITY_BPS_SLOT — normalized bps delta computed in afterSwap
 *   3. SWAP_ACTIVE_SLOT    — reentrancy guard, ALWAYS cleared in afterSwap
 *
 * Critical fix: previous version set SWAP_ACTIVE_SLOT in beforeSwap but
 * never cleared it, permanently bricking the pool after the first swap.
 */
contract NULLAIHooks is BaseHook {
    using PoolIdLibrary for PoolKey;

    bytes32 private constant PRE_SWAP_PRICE_SLOT = keccak256("nullai.hook.pre_swap_price");
    bytes32 private constant VOLATILITY_BPS_SLOT = keccak256("nullai.hook.volatility_bps");
    bytes32 private constant SWAP_ACTIVE_SLOT    = keccak256("nullai.hook.swap_active");

    IBurnEngine public burnEngine;
    uint256 public maxLPVolatilityBps = 500;

    event VolatilityRecorded(PoolId indexed poolId, uint256 volatilityBps);
    event LiquidityBlocked(PoolId indexed poolId, uint256 volatilityBps);

    constructor(IPoolManager _poolManager, address _burnEngine) BaseHook(_poolManager) {
        require(_burnEngine != address(0), "NULLAIHooks: zero burnEngine");
        burnEngine = IBurnEngine(_burnEngine);
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false, afterInitialize: false,
            beforeAddLiquidity: true, afterAddLiquidity: false,
            beforeRemoveLiquidity: false, afterRemoveLiquidity: false,
            beforeSwap: true, afterSwap: true,
            beforeDonate: false, afterDonate: false,
            beforeSwapReturnDelta: false, afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false, afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external override onlyPoolManager returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint256 swapActive;
        assembly { swapActive := tload(SWAP_ACTIVE_SLOT) }
        require(swapActive == 0, "NULLAIHooks: reentrant swap");

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(key.toId());
        assembly {
            tstore(PRE_SWAP_PRICE_SLOT, sqrtPriceX96)
            tstore(SWAP_ACTIVE_SLOT, 1)
        }
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external override onlyPoolManager returns (bytes4, int128)
    {
        // Always clear guard first — even on revert paths.
        assembly { tstore(SWAP_ACTIVE_SLOT, 0) }

        (uint160 sqrtPriceAfter, , , ) = poolManager.getSlot0(key.toId());
        uint256 sqrtPriceBefore;
        assembly { sqrtPriceBefore := tload(PRE_SWAP_PRICE_SLOT) }

        if (sqrtPriceBefore > 0) {
            uint256 delta = sqrtPriceAfter > sqrtPriceBefore
                ? uint256(sqrtPriceAfter) - sqrtPriceBefore
                : sqrtPriceBefore - uint256(sqrtPriceAfter);

            // Normalized: delta / sqrtPriceBefore in bps
            uint256 volatilityBps = (delta * 10_000) / sqrtPriceBefore;
            assembly { tstore(VOLATILITY_BPS_SLOT, volatilityBps) }

            if (address(burnEngine) != address(0)) {
                try burnEngine.recordVolatility(volatilityBps) {} catch {}
            }
            emit VolatilityRecorded(key.toId(), volatilityBps);
        }
        return (BaseHook.afterSwap.selector, 0);
    }

    function beforeAddLiquidity(address, PoolKey calldata key, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external override onlyPoolManager returns (bytes4)
    {
        uint256 volatilityBps;
        assembly { volatilityBps := tload(VOLATILITY_BPS_SLOT) }
        if (volatilityBps > maxLPVolatilityBps) {
            emit LiquidityBlocked(key.toId(), volatilityBps);
            revert("NULLAIHooks: LP blocked — high volatility");
        }
        return BaseHook.beforeAddLiquidity.selector;
    }

    function getCurrentTxVolatility() external view returns (uint256 bps) {
        assembly { bps := tload(VOLATILITY_BPS_SLOT) }
    }

    function setMaxLPVolatilityBps(uint256 bps) external {
        require(bps <= 2_000, "NULLAIHooks: cap at 20%");
        maxLPVolatilityBps = bps;
    }
}
