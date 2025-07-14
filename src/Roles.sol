pragma solidity ^0.8.30;

library Roles {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MULTISIG_ADMIN_ROLE = keccak256("MULTISIG_ADMIN_ROLE");
    bytes32 public constant ALLOWED_EIP712_SWAP_ROLE = keccak256("ALLOWED_EIP712_SWAP_ROLE");
}
