// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./ISwap.sol";

contract FeeManager is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    uint256 public constant FEE_DENOMINATOR = 10000;

    uint256 public fee;

    function initialize(uint256 _fee) external initializer {
        _disableInitializers();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        fee = _fee;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fee = _fee;
    }

    function getFee(ISwap.SwapParams memory swapParams) external view returns (uint256) {
        return (swapParams.amount0 * fee) / FEE_DENOMINATOR;
    }
}
