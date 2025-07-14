// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/AccessManager.sol";
import "../src/Roles.sol";

contract AccessManagerTest is Test {
    AccessManager public accessManager;
    address public admin;
    address public multisigAdmin1;
    address public eip712Swapper1;
    address public nonAdmin;

    function setUp() public {
        admin = makeAddr("admin");
        multisigAdmin1 = makeAddr("multisigAdmin1");
        eip712Swapper1 = makeAddr("eip712Swapper1");
        nonAdmin = makeAddr("nonAdmin");

        vm.prank(admin);
        accessManager = new AccessManager();
    }

    function test_InitialState() public view {
        // Admin should have DEFAULT_ADMIN_ROLE
        assertTrue(accessManager.hasRole(accessManager.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_AddAndRemoveAdmin() public {
        vm.startPrank(admin);

        // Add admin
        accessManager.addAdmin(multisigAdmin1);
        assertTrue(accessManager.isAdmin(multisigAdmin1));
        assertTrue(accessManager.hasRole(Roles.ADMIN_ROLE, multisigAdmin1));

        // Remove admin
        accessManager.removeAdmin(multisigAdmin1);
        assertFalse(accessManager.isAdmin(multisigAdmin1));
        assertFalse(accessManager.hasRole(Roles.ADMIN_ROLE, multisigAdmin1));

        vm.stopPrank();
    }

    function test_AddAndRemoveMultisigAdmin() public {
        vm.startPrank(admin);

        // Add multisig admin
        accessManager.addMultisigAdmin(multisigAdmin1);
        assertTrue(accessManager.isMultisigAdmin(multisigAdmin1));
        assertTrue(accessManager.hasRole(Roles.MULTISIG_ADMIN_ROLE, multisigAdmin1));

        // Remove multisig admin
        accessManager.removeMultisigAdmin(multisigAdmin1);
        assertFalse(accessManager.isMultisigAdmin(multisigAdmin1));
        assertFalse(accessManager.hasRole(Roles.MULTISIG_ADMIN_ROLE, multisigAdmin1));

        vm.stopPrank();
    }

    function test_AddAndRemoveEIP712Swapper() public {
        vm.startPrank(admin);

        // Add EIP712 swapper
        accessManager.addEIP712Swapper(eip712Swapper1);
        assertTrue(accessManager.isEIP712Swapper(eip712Swapper1));
        assertTrue(accessManager.hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, eip712Swapper1));

        // Remove EIP712 swapper
        accessManager.removeEIP712Swapper(eip712Swapper1);
        assertFalse(accessManager.isEIP712Swapper(eip712Swapper1));
        assertFalse(accessManager.hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, eip712Swapper1));

        vm.stopPrank();
    }

    function test_RevertWhen_NotAuthorized() public {
        vm.startPrank(nonAdmin);

        vm.expectRevert();
        accessManager.addAdmin(multisigAdmin1);

        vm.expectRevert();
        accessManager.addMultisigAdmin(multisigAdmin1);

        vm.expectRevert();
        accessManager.addEIP712Swapper(eip712Swapper1);

        vm.stopPrank();
    }
}
