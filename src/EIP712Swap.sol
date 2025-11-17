// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./LiquidityPool.sol";
import "./ISwap.sol";

contract EIP712Swap is EIP712 {
    using ECDSA for bytes32;

    mapping(address => uint256) private _nonces;

    bytes32 private constant SWAP_TYPEHASH =
        keccak256(
            "SwapRequest(address pool,address sender,address tokenIn,address tokenOut,uint256 amountIn,uint256 minAmountOut,uint256 nonce,uint256 deadline)"
        );

    error InvalidSignature();
    error ExpiredSwapRequest();
    error InvalidNonce();

    constructor() EIP712("EIP712Swap", "1") {}

    function getDomainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function getNonce(address _sender) public view returns (uint256) {
        return _nonces[_sender];
    }

    function verify(
        ISwap.SwapRequest memory _swapRequest,
        bytes memory _signature
    ) public view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SWAP_TYPEHASH,
                    _swapRequest.pool,
                    _swapRequest.sender,
                    _swapRequest.tokenIn,
                    _swapRequest.tokenOut,
                    _swapRequest.amountIn,
                    _swapRequest.minAmountOut,
                    _swapRequest.nonce,
                    _swapRequest.deadline
                )
            )
        );
        address signer = digest.recover(_signature);
        return signer == _swapRequest.sender;
    }

    function executeSwap(
        ISwap.SwapRequest memory _swapRequest,
        bytes memory _signature
    ) public returns (bool) {
        if (!verify(_swapRequest, _signature)) revert InvalidSignature();
        if (_swapRequest.deadline < block.timestamp) {
            revert ExpiredSwapRequest();
        }
        if (_swapRequest.nonce != _nonces[_swapRequest.sender]) {
            revert InvalidNonce();
        }

        _nonces[_swapRequest.sender]++;
        LiquidityPool(_swapRequest.pool).swap(
            _swapRequest.sender,
            _swapRequest.tokenIn,
            _swapRequest.tokenOut,
            _swapRequest.amountIn,
            _swapRequest.minAmountOut
        );

        return true;
    }
}
