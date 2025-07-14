// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/FeeManager.sol";
import "../src/ISwap.sol";

contract FeeManagerTest is Test {
    FeeManager public feeManager;
    address public admin;
    address public nonAdmin;

    function setUp() public {
        admin = address(this);
        nonAdmin = makeAddr("nonAdmin");

        FeeManager implementation = new FeeManager();
        bytes memory initData = abi.encodeWithSignature("initialize(uint256)", 250);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        feeManager = FeeManager(address(proxy));
    }

    function test_Initialize() public view {
        assertEq(feeManager.fee(), 250);
        assertEq(feeManager.FEE_DENOMINATOR(), 10000);
        assertTrue(feeManager.hasRole(feeManager.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_SetFee() public {
        feeManager.setFee(500);
        assertEq(feeManager.fee(), 500);
    }

    function test_SetFee_RevertWhen_NotAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert();
        feeManager.setFee(500);
    }

    function test_GetFee() public view {
        ISwap.SwapParams memory params = ISwap.SwapParams({
            token0: address(0x1),
            token1: address(0x2),
            amount0: 1000e18,
            reserveToken0: 10000e18,
            reserveToken1: 20000e6
        });

        uint256 fee = feeManager.getFee(params);
        assertGt(fee, 0);

        // Test that fee is reasonable (should be less than the input amount)
        assertLt(fee, params.amount0);
    }

    function test_GetFee_WithDifferentAmounts() public view {
        ISwap.SwapParams memory params = ISwap.SwapParams({
            token0: address(0x1),
            token1: address(0x2),
            amount0: 500e18,
            reserveToken0: 5000e18,
            reserveToken1: 10000e6
        });

        uint256 fee = feeManager.getFee(params);
        assertGt(fee, 0);
    }

    function test_GetFee_ZeroAmount() public view {
        ISwap.SwapParams memory params = ISwap.SwapParams({
            token0: address(0x1),
            token1: address(0x2),
            amount0: 0,
            reserveToken0: 10000e18,
            reserveToken1: 20000e6
        });

        uint256 fee = feeManager.getFee(params);
        assertEq(fee, 0);
    }

    function test_FeeCalculationWithSimpleNumbers() public view {
        // Use numbers that result in clean division
        ISwap.SwapParams memory params = ISwap.SwapParams({
            token0: address(0x1),
            token1: address(0x2),
            amount0: 1000,
            reserveToken0: 10000,
            reserveToken1: 10000
        });

        uint256 fee = feeManager.getFee(params);

        // Just verify fee is calculated (should be > 0 for non-zero input)
        assertGt(fee, 0);

        // Verify fee is proportional to fee rate (250 basis points = 2.5%)
        // Fee should be roughly 2.5% of the calculated output amount
        assertLt(fee, 1000); // Should be much less than input
    }

    function test_FeeScalesWithAmount() public view {
        // Test that larger amounts result in larger fees
        ISwap.SwapParams memory smallParams = ISwap.SwapParams({
            token0: address(0x1),
            token1: address(0x2),
            amount0: 100e18,
            reserveToken0: 10000e18,
            reserveToken1: 10000e6
        });

        ISwap.SwapParams memory largeParams = ISwap.SwapParams({
            token0: address(0x1),
            token1: address(0x2),
            amount0: 1000e18, // 10x larger
            reserveToken0: 10000e18,
            reserveToken1: 10000e6
        });

        uint256 smallFee = feeManager.getFee(smallParams);
        uint256 largeFee = feeManager.getFee(largeParams);

        assertGt(largeFee, smallFee);
    }

    function test_FeeWithDifferentRates() public {
        // Test different fee rates
        feeManager.setFee(500); // 5%

        ISwap.SwapParams memory params = ISwap.SwapParams({
            token0: address(0x1),
            token1: address(0x2),
            amount0: 1000e18,
            reserveToken0: 10000e18,
            reserveToken1: 10000e6
        });

        uint256 feeAt5Percent = feeManager.getFee(params);

        // Change to 1%
        feeManager.setFee(100);
        uint256 feeAt1Percent = feeManager.getFee(params);

        // Higher rate should result in higher fee
        assertGt(feeAt5Percent, feeAt1Percent);
    }
}
