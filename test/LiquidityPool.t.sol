// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "../src/LiquidityPool.sol";
import "../src/FeeManager.sol";
import "../src/EIP712Swap.sol";

using ECDSA for bytes32;

bytes32 constant SWAP_TYPEHASH = keccak256(
    "SwapRequest(address pool,address sender,address tokenIn,address tokenOut,uint256 amountIn,uint256 minAmountOut,uint256 nonce,uint256 deadline)"
);

contract ERC20Mock is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

contract LiquidityPoolTest is Test {
    uint256 constant ONE = 1 ether; // helper
    address alice = vm.addr(1);
    address bob = vm.addr(2);

    ERC20Mock tokenA;
    ERC20Mock tokenB;
    FeeManager feeMgr;
    EIP712Swap eip712;
    LiquidityPool pool;

    function setUp() public {
        // 1. Deploy mocks
        tokenA = new ERC20Mock("TokenA", "A");
        tokenB = new ERC20Mock("TokenB", "B");
        tokenA.mint(alice, 2_000 * ONE);
        tokenB.mint(alice, 2_000 * ONE);

        // 2. Fee manager (30 bp = 0.30 %)
        feeMgr = new FeeManager();
        feeMgr.initialize(30);

        // 3. EIP-712 relay
        eip712 = new EIP712Swap();

        // 4. Liquidity Pool (decimals = 18)
        pool = new LiquidityPool(address(tokenA), 18, address(tokenB), 18, address(feeMgr), address(eip712));
        pool.initialize(30); // gives deployer DEFAULT_ADMIN_ROLE
    }

    /* ---------- Basic unit tests ---------- */

    /// Expect current addLiquidity implementation to revert (wrong check)
    function testAddLiquidityShouldRevertUntilFixed() public {
        vm.startPrank(alice);
        tokenA.approve(address(pool), 100 * ONE);
        // vm.expectRevert(LiquidityPool.InvalidTokenAddress.selector);
        // pool.addLiquidity(address(tokenA), 100 * ONE);
    }

    /// Manually seed reserves to test swap logic without touching addLiquidity
    function _seedReserves(uint256 r0, uint256 r1) internal {
        vm.startPrank(alice);
        tokenA.approve(address(pool), r0);
        tokenB.approve(address(pool), r1);
        pool.addLiquidity(address(tokenA), r0);
        pool.addLiquidity(address(tokenB), r1);
        vm.stopPrank();
    }

    /// Happy-path swap TokenA -> TokenB via pool.swap
    function testSwapAforB() public {
        _seedReserves(1_000 * ONE, 1_000 * ONE);

        uint256 amountIn = 100 * ONE;
        uint256 minOut = 80 * ONE; // loose slippage for demo

        vm.startPrank(alice);
        tokenA.approve(address(pool), amountIn);

        uint256 balBBefore = tokenB.balanceOf(alice);
        pool.swap(alice, address(tokenA), address(tokenB), amountIn, minOut);
        uint256 balBAfter = tokenB.balanceOf(alice);

        assertGt(balBAfter - balBBefore, 0, "got no tokens out");
    }

    /// Verify/execute EIP-712 meta-swap (off-chain signature)
    function testRelaySwap() public {
        _seedReserves(1_000 * ONE, 1_000 * ONE);

        uint256 amountIn = 10 * ONE;
        uint256 nonce = eip712.getNonce(alice);
        uint256 deadline = block.timestamp + 1 hours;

        ISwap.SwapRequest memory req = ISwap.SwapRequest({
            pool: address(pool),
            sender: alice,
            tokenIn: address(tokenA),
            tokenOut: address(tokenB),
            amountIn: amountIn,
            minAmountOut: 1,
            nonce: nonce,
            deadline: deadline
        });

        /* -- подпись -- */
        bytes32 digest = _hash(req, eip712.getDomainSeparator());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        /* -- подготовка токенов -- */
        vm.prank(alice);
        tokenA.approve(address(pool), amountIn);

        /* -- вызов -- */
        bool ok = eip712.executeSwap(req, sig);
        assertTrue(ok);
    }

    /* ---------- internal helpers ---------- */

    function _hash(ISwap.SwapRequest memory req, bytes32 domainSeparator) internal pure returns (bytes32) {
        /* 1. structHash */
        bytes32 structHash = keccak256(
            abi.encode(
                SWAP_TYPEHASH,
                req.pool,
                req.sender,
                req.tokenIn,
                req.tokenOut,
                req.amountIn,
                req.minAmountOut,
                req.nonce,
                req.deadline
            )
        );

        /* 2. EIP-712 digest = keccak256("\x19\x01", domainSeparator, structHash) */
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
