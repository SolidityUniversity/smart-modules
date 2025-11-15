// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./ISwap.sol";

contract FeeManager is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public fee; // Fee in basis points (e.g., 250 = 2.5%)

    function initialize(uint256 _fee) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        fee = _fee;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setFee(uint256 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fee = _fee;
    }

    /// @notice Calculate absolute fee amount for a swap
    /// @param swapParams The swap parameters
    /// @return Absolute fee amount in output token units
    function getFee(ISwap.SwapParams memory swapParams) external view returns (uint256) {
        // Calculate fee based on input amount and convert to output token equivalent
        uint256 amountOut =
            (swapParams.amount0 * swapParams.reserveToken1) / (swapParams.reserveToken0 + swapParams.amount0);
        return (amountOut * fee) / FEE_DENOMINATOR;
    }
}
