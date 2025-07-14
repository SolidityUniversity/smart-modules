// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/LiquidityPool.sol";
import "../src/FeeManager.sol";
import "../src/EIP712Swap.sol";
import "../src/Roles.sol"; // Import Roles library
import "./MockERC20.sol";

contract LiquidityPoolTest is Test {
    LiquidityPool public pool;
    FeeManager public feeManager;
    EIP712Swap public eip712Swap;
    MockERC20 public token0;
    MockERC20 public token1;

    address public admin;
    address public user;

    function setUp() public {
        admin = address(this);
        user = makeAddr("user");

        // Deploy FeeManager with proxy
        FeeManager feeManagerImpl = new FeeManager();
        bytes memory initData = abi.encodeWithSignature("initialize(uint256)", 250);
        ERC1967Proxy feeManagerProxy = new ERC1967Proxy(address(feeManagerImpl), initData);
        feeManager = FeeManager(address(feeManagerProxy));

        eip712Swap = new EIP712Swap();

        // Deploy tokens
        token0 = new MockERC20("Token0", "TK0", 18, 1000000e18);
        token1 = new MockERC20("Token1", "TK1", 6, 1000000e6);

        // Deploy pool
        pool = new LiquidityPool(address(token0), 18, address(token1), 6, address(feeManager), address(eip712Swap));

        // Setup user tokens
        token0.mint(user, 10000e18);
        token1.mint(user, 10000e6);

        vm.startPrank(user);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        // Admin approvals
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
    }

    function test_RoleBasedAccess() public view {
        // Admin should have ADMIN_ROLE - use Roles library
        assertTrue(pool.hasRole(Roles.ADMIN_ROLE, admin));

        // EIP712Swap should have ALLOWED_EIP712_SWAP_ROLE - use Roles library
        assertTrue(pool.hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, address(eip712Swap)));

        // User should have no roles
        assertFalse(pool.hasRole(Roles.ADMIN_ROLE, user));
        assertFalse(pool.hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, user));
    }

    function test_AddLiquidity() public {
        pool.addLiquidity(address(token0), 1000e18);
        assertEq(pool.reserveToken0(), 1000e18);
    }

    function test_AddLiquidity_RevertWhen_InvalidToken() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18, 1000e18);
        vm.expectRevert(abi.encodeWithSelector(LiquidityPool.InvalidTokenAddress.selector, address(invalidToken)));
        pool.addLiquidity(address(invalidToken), 1000e18);
    }

    function test_AddLiquidity_RevertWhen_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        pool.addLiquidity(address(token0), 1000e18);
    }

    function test_Swap() public {
        // Add liquidity
        pool.addLiquidity(address(token0), 10000e18);
        pool.addLiquidity(address(token1), 20000e6);

        uint256 userBalanceBefore = token0.balanceOf(user);

        pool.swap(user, address(token0), address(token1), 100e18, 0);

        assertEq(token0.balanceOf(user), userBalanceBefore - 100e18);
        assertGt(token1.balanceOf(user), 10000e6); // Should receive some token1
    }

    function test_EIP712SwapCanExecuteSwap() public {
        // Add liquidity
        pool.addLiquidity(address(token0), 10000e18);
        pool.addLiquidity(address(token1), 20000e6);

        uint256 userBalanceBefore = token0.balanceOf(user);

        // EIP712Swap contract can call swap because it has ALLOWED_EIP712_SWAP_ROLE
        vm.prank(address(eip712Swap));
        pool.swap(user, address(token0), address(token1), 100e18, 0);

        assertEq(token0.balanceOf(user), userBalanceBefore - 100e18);
    }

    function test_GrantAndRevokeSwapRole() public {
        address newSwapper = makeAddr("newSwapper");

        // Initially should not have role
        assertFalse(pool.hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, newSwapper));

        // Grant role
        pool.grantSwapRole(newSwapper);
        assertTrue(pool.hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, newSwapper));

        // Revoke role
        pool.revokeSwapRole(newSwapper);
        assertFalse(pool.hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, newSwapper));
    }

    function test_OnlyAuthorizedCanSwap() public {
        pool.addLiquidity(address(token0), 10000e18);
        pool.addLiquidity(address(token1), 20000e6);

        // Random user cannot call swap
        vm.prank(user);
        vm.expectRevert("Not authorized for swap operations");
        pool.swap(user, address(token0), address(token1), 100e18, 0);
    }

    function test_RemoveLiquidity() public {
        // Add liquidity first
        pool.addLiquidity(address(token0), 1000e18);
        assertEq(pool.reserveToken0(), 1000e18);

        uint256 balanceBefore = token0.balanceOf(admin);

        // Remove some liquidity
        pool.removeLiquidity(address(token0), 500e18);

        assertEq(pool.reserveToken0(), 500e18);
        assertEq(token0.balanceOf(admin), balanceBefore + 500e18);
    }

    function test_Swap_RevertWhen_InsufficientLiquidity() public {
        pool.addLiquidity(address(token0), 100e18);
        pool.addLiquidity(address(token1), 50e6);

        vm.expectRevert(LiquidityPool.InsufficientLiquidity.selector);
        pool.swap(user, address(token0), address(token1), 100e18, 0); // 100% of reserves
    }

    function test_Swap_RevertWhen_InvalidTokenPair() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV", 18, 1000e18);
        vm.expectRevert();
        pool.swap(user, address(invalidToken), address(token1), 100e18, 1);
    }

    function test_GetPrice() public {
        pool.addLiquidity(address(token0), 1000e18);
        pool.addLiquidity(address(token1), 2000e6);

        uint256 price = pool.getPrice(address(token0), address(token1));
        assertGt(price, 0);
    }
}
