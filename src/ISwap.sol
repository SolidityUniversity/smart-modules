// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ISwap {
    /// @notice Parameters for the swap
    /// @param token0 The address of the first token
    /// @param token1 The address of the second token
    /// @param amount0 The amount of the first token to swap
    /// @param reserveToken0 The reserve of the first token
    /// @param reserveToken1 The reserve of the second token
    struct SwapParams {
        address token0;
        address token1;
        uint256 amount0;
        uint256 reserveToken0;
        uint256 reserveToken1;
    }

    /// @notice Parameters for the swap request
    /// @param pool The address of the pool
    /// @param sender The address of the sender
    /// @param tokenIn The address of the token to swap in
    /// @param tokenOut The address of the token to swap out
    /// @param amountIn The amount of the token to swap in
    /// @param minAmountOut The minimum amount of the token to swap out
    /// @param nonce The nonce of the swap
    /// @param deadline The deadline of the swap
    struct SwapRequest {
        address pool;
        address sender;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 nonce;
        uint256 deadline;
    }
}
