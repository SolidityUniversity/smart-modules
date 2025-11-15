// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/Roles.sol";

contract RolesTest is Test {
    function test_RoleConstants() public pure {
        // Test that role constants are properly defined and unique
        assertNotEq(Roles.ADMIN_ROLE, Roles.MULTISIG_ADMIN_ROLE);
        assertNotEq(Roles.ADMIN_ROLE, Roles.ALLOWED_EIP712_SWAP_ROLE);
        assertNotEq(Roles.MULTISIG_ADMIN_ROLE, Roles.ALLOWED_EIP712_SWAP_ROLE);

        // Test that roles have expected values (keccak256 hashes)
        assertEq(Roles.ADMIN_ROLE, keccak256("ADMIN_ROLE"));
        assertEq(Roles.MULTISIG_ADMIN_ROLE, keccak256("MULTISIG_ADMIN_ROLE"));
        assertEq(Roles.ALLOWED_EIP712_SWAP_ROLE, keccak256("ALLOWED_EIP712_SWAP_ROLE"));
    }

    function test_RoleUniqueness() public pure {
        assertTrue(Roles.ADMIN_ROLE != Roles.MULTISIG_ADMIN_ROLE);
    }
}
