pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./Roles.sol";
contract AccessManager is AccessControl {
    using Roles for bytes32;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(Roles.MULTISIG_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
    }

    function addMultisigAdmin(address _multisigAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(Roles.MULTISIG_ADMIN_ROLE, _multisigAdmin);
    }

    function removeMultisigAdmin(address _multisigAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(Roles.MULTISIG_ADMIN_ROLE, _multisigAdmin);
    }

    function isMultisigAdmin(address _address) external view returns (bool) {
        return hasRole(Roles.MULTISIG_ADMIN_ROLE, _address);
    }
}