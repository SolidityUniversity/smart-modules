// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Roles.sol";
import "../src/EIP712Swap.sol";
import "../src/LiquidityPool.sol";
import "../src/FeeManager.sol";
import "../src/ISwap.sol";
import "./MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EIP712SwapTest is Test {
    EIP712Swap eip712Swap;
    FeeManager feeManager;
    LiquidityPool pool;
    address poolAddress;
    address user;
    uint256 userPrivateKey;
    MockERC20 token0;
    MockERC20 token1;

    function setUp() public {
        userPrivateKey = 0x1234;
        user = vm.addr(userPrivateKey);

        // Deploy contracts
        eip712Swap = new EIP712Swap();

        // Deploy FeeManager with proxy
        FeeManager feeManagerImpl = new FeeManager();
        bytes memory feeManagerInitData = abi.encodeWithSignature("initialize(uint256)", 250);
        ERC1967Proxy feeManagerProxy = new ERC1967Proxy(address(feeManagerImpl), feeManagerInitData);
        feeManager = FeeManager(address(feeManagerProxy));

        // Deploy mock tokens
        token0 = new MockERC20("Token0", "TK0", 18, 1000000e18);
        token1 = new MockERC20("Token1", "TK1", 18, 1000000e18);

        // Deploy pool
        pool = new LiquidityPool(address(token0), 18, address(token1), 18, address(feeManager), address(eip712Swap));
        poolAddress = address(pool);

        // The pool constructor should have already granted ALLOWED_EIP712_SWAP_ROLE to eip712Swap
        // But let's verify it's set up correctly
        assertTrue(pool.hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, address(eip712Swap)));

        // Setup tokens for user
        token0.mint(user, 10000e18);
        token1.mint(user, 10000e18);

        vm.startPrank(user);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // Admin needs tokens to add liquidity
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
    }

    function test_ExecuteSwap_Success() public {
        // First, add liquidity to the pool so swaps can work
        pool.addLiquidity(address(token0), 10000e18);
        pool.addLiquidity(address(token1), 10000e18);

        // Check initial balances
        uint256 userToken0Before = token0.balanceOf(user);
        uint256 userToken1Before = token1.balanceOf(user);
        uint256 initialNonce = eip712Swap.getNonce(user);

        // Create a valid swap request
        ISwap.SwapRequest memory swapRequest = ISwap.SwapRequest({
            pool: poolAddress,
            sender: user,
            tokenIn: address(token0),
            tokenOut: address(token1),
            amountIn: 100e18,
            minAmountOut: 0, // Set to 0 to avoid slippage issues
            nonce: initialNonce,
            deadline: block.timestamp + 1 hours
        });

        // Sign the request
        bytes memory signature = _signSwapRequest(swapRequest, userPrivateKey);

        // Verify the signature is valid
        assertTrue(eip712Swap.verify(swapRequest, signature));

        // Execute the swap
        bool success = eip712Swap.executeSwap(swapRequest, signature);
        assertTrue(success);

        // Verify the swap worked
        assertEq(token0.balanceOf(user), userToken0Before - 100e18); // User lost token0
        assertGt(token1.balanceOf(user), userToken1Before); // User gained token1
        assertEq(eip712Swap.getNonce(user), initialNonce + 1); // Nonce incremented
    }

    function test_ExecuteSwap_MultipleSwaps() public {
        // Add liquidity
        pool.addLiquidity(address(token0), 10000e18);
        pool.addLiquidity(address(token1), 10000e18);

        // Execute first swap
        ISwap.SwapRequest memory firstSwap = ISwap.SwapRequest({
            pool: poolAddress,
            sender: user,
            tokenIn: address(token0),
            tokenOut: address(token1),
            amountIn: 100e18,
            minAmountOut: 0,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory firstSignature = _signSwapRequest(firstSwap, userPrivateKey);
        assertTrue(eip712Swap.executeSwap(firstSwap, firstSignature));
        assertEq(eip712Swap.getNonce(user), 1);

        // Execute second swap with incremented nonce
        ISwap.SwapRequest memory secondSwap = ISwap.SwapRequest({
            pool: poolAddress,
            sender: user,
            tokenIn: address(token1),
            tokenOut: address(token0),
            amountIn: 50e18,
            minAmountOut: 0,
            nonce: 1, // Incremented nonce
            deadline: block.timestamp + 1 hours
        });

        bytes memory secondSignature = _signSwapRequest(secondSwap, userPrivateKey);
        assertTrue(eip712Swap.executeSwap(secondSwap, secondSignature));
        assertEq(eip712Swap.getNonce(user), 2);
    }

    function test_ExecuteSwap_RevertWhen_InsufficientLiquidity() public {
        // Don't add liquidity - pool should be empty

        ISwap.SwapRequest memory swapRequest = ISwap.SwapRequest({
            pool: poolAddress,
            sender: user,
            tokenIn: address(token0),
            tokenOut: address(token1),
            amountIn: 100e18,
            minAmountOut: 0,
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory signature = _signSwapRequest(swapRequest, userPrivateKey);

        // Should revert due to insufficient liquidity in the pool
        vm.expectRevert(LiquidityPool.InsufficientLiquidity.selector);
        eip712Swap.executeSwap(swapRequest, signature);

        // Nonce should not increment on failed swap
        assertEq(eip712Swap.getNonce(user), 0);
    }

    function _signSwapRequest(ISwap.SwapRequest memory swapRequest, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "SwapRequest(address pool,address sender,address tokenIn,address tokenOut,uint256 amountIn,uint256 minAmountOut,uint256 nonce,uint256 deadline)"
                ),
                swapRequest.pool,
                swapRequest.sender,
                swapRequest.tokenIn,
                swapRequest.tokenOut,
                swapRequest.amountIn,
                swapRequest.minAmountOut,
                swapRequest.nonce,
                swapRequest.deadline
            )
        );

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", eip712Swap.getDomainSeparator(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }
}
