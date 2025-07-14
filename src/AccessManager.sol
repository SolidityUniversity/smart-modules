pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Roles.sol";

contract AccessManager is AccessControl {
    using Roles for bytes32;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // Set role admin relationships
        _setRoleAdmin(Roles.ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.MULTISIG_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.ALLOWED_EIP712_SWAP_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function addAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(Roles.ADMIN_ROLE, _admin);
    }

    function removeAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(Roles.ADMIN_ROLE, _admin);
    }

    function addMultisigAdmin(address _multisigAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(Roles.MULTISIG_ADMIN_ROLE, _multisigAdmin);
    }

    function removeMultisigAdmin(address _multisigAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(Roles.MULTISIG_ADMIN_ROLE, _multisigAdmin);
    }

    function addEIP712Swapper(address _swapper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(Roles.ALLOWED_EIP712_SWAP_ROLE, _swapper);
    }

    function removeEIP712Swapper(address _swapper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(Roles.ALLOWED_EIP712_SWAP_ROLE, _swapper);
    }

    function isAdmin(address _address) external view returns (bool) {
        return hasRole(Roles.ADMIN_ROLE, _address);
    }

    function isMultisigAdmin(address _address) external view returns (bool) {
        return hasRole(Roles.MULTISIG_ADMIN_ROLE, _address);
    }

    function isEIP712Swapper(address _address) external view returns (bool) {
        return hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, _address);
    }
}
