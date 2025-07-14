pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./ISwap.sol";
import "./FeeManager.sol";
import "./EIP712Swap.sol";
import "./Roles.sol";

contract LiquidityPool is ISwap, AccessControl {
    using Roles for bytes32;

    address public token0;
    uint256 public token0Decimals;
    address public token1;
    uint256 public token1Decimals;
    uint256 public reserveToken0;
    uint256 public reserveToken1;
    FeeManager public feeManager;
    EIP712Swap public eip712Swap;

    modifier onlyAdminOrEIP712Swap() {
        require(
            hasRole(Roles.ADMIN_ROLE, msg.sender) || hasRole(Roles.ALLOWED_EIP712_SWAP_ROLE, msg.sender),
            "Not authorized for swap operations"
        );
        _;
    }

    event LiquidityAdded(address indexed _token, uint256 _amount);
    event Swap(address indexed _tokenIn, address indexed _tokenOut, uint256 _amountIn, uint256 _amountOut);

    error InsufficientTokenBalance();
    error InvalidTokenAddress(address _token);
    error InvalidTokenPair(address _tokenIn, address _tokenOut);
    error InsufficientLiquidity();
    error InsufficientOutputAmount(uint256 expected, uint256 actual);
    error InsufficientAllowance();

    constructor(
        address _token0,
        uint256 _token0Decimals,
        address _token1,
        uint256 _token1Decimals,
        address _feeManager,
        address _eip712Swap
    ) {
        token0 = _token0;
        token0Decimals = _token0Decimals;
        token1 = _token1;
        token1Decimals = _token1Decimals;
        feeManager = FeeManager(_feeManager);
        eip712Swap = EIP712Swap(_eip712Swap);

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(Roles.ADMIN_ROLE, msg.sender);

        // Grant EIP712Swap contract permission to execute swaps
        _grantRole(Roles.ALLOWED_EIP712_SWAP_ROLE, _eip712Swap);

        // Set role admin relationships
        _setRoleAdmin(Roles.ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.ALLOWED_EIP712_SWAP_ROLE, DEFAULT_ADMIN_ROLE);
    }

    /// @notice Add liquidity to the pool (admin only)
    function addLiquidity(address _token, uint256 _amount) external onlyRole(Roles.ADMIN_ROLE) {
        if (_token != token0 && _token != token1) {
            revert InvalidTokenAddress(_token);
        }

        if (IERC20(_token).balanceOf(msg.sender) < _amount) {
            revert InsufficientTokenBalance();
        }

        require(IERC20(_token).transferFrom(msg.sender, address(this), _amount));

        if (_token == token0) {
            reserveToken0 += _amount;
        } else {
            reserveToken1 += _amount;
        }

        emit LiquidityAdded(_token, _amount);
    }

    /// @notice Remove liquidity from the pool (admin only)
    function removeLiquidity(address _token, uint256 _amount) external onlyRole(Roles.ADMIN_ROLE) {
        if (_token != token0 && _token != token1) {
            revert InvalidTokenAddress(_token);
        }

        uint256 currentReserve = _token == token0 ? reserveToken0 : reserveToken1;
        require(_amount <= currentReserve, "Insufficient reserves");

        require(IERC20(_token).transfer(msg.sender, _amount));

        if (_token == token0) {
            reserveToken0 -= _amount;
        } else {
            reserveToken1 -= _amount;
        }
    }

    /// @notice Grant EIP712 swap permission to an address
    function grantSwapRole(address _swapper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(Roles.ALLOWED_EIP712_SWAP_ROLE, _swapper);
    }

    /// @notice Revoke EIP712 swap permission from an address
    function revokeSwapRole(address _swapper) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(Roles.ALLOWED_EIP712_SWAP_ROLE, _swapper);
    }

    function getReserves() external view returns (uint256 _reserveToken0, uint256 _reserveToken1) {
        _reserveToken0 = reserveToken0;
        _reserveToken1 = reserveToken1;
    }

    function getPrice(address _tokenIn, address _tokenOut) external view returns (uint256 _price) {
        uint256 _reserveTokenIn = _tokenIn == token0 ? reserveToken0 : reserveToken1;
        uint256 _reserveTokenOut = _tokenOut == token0 ? reserveToken0 : reserveToken1;

        if (_reserveTokenIn == 0 || _reserveTokenOut == 0) {
            return 0;
        }

        _price = (_reserveTokenOut * 1e18) / _reserveTokenIn;
    }

    /// @notice Execute a swap (admin or authorized EIP712 contract only)
    function swap(address _sender, address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _minAmountOut)
        external
        onlyAdminOrEIP712Swap
    {
        if (
            _tokenIn != token0 && _tokenIn != token1 || _tokenOut != token0 && _tokenOut != token1
                || _tokenIn == _tokenOut
        ) {
            revert InvalidTokenPair(_tokenIn, _tokenOut);
        }

        address tokenHolder = _sender;

        if (IERC20(_tokenIn).allowance(tokenHolder, address(this)) < _amountIn) revert InsufficientAllowance();

        uint256 _reserveTokenIn = _tokenIn == token0 ? reserveToken0 : reserveToken1;
        uint256 _reserveTokenOut = _tokenOut == token0 ? reserveToken0 : reserveToken1;

        if (_reserveTokenIn == 0 || _reserveTokenOut == 0) revert InsufficientLiquidity();
        if (_amountIn >= _reserveTokenIn) revert InsufficientLiquidity();

        // AMM calculation
        uint256 amountOut = (_amountIn * _reserveTokenOut) / (_reserveTokenIn + _amountIn);

        // Apply fee using FeeManager
        ISwap.SwapParams memory swapParams = ISwap.SwapParams({
            token0: _tokenIn,
            token1: _tokenOut,
            amount0: _amountIn,
            reserveToken0: _reserveTokenIn,
            reserveToken1: _reserveTokenOut
        });

        uint256 feeAmount = feeManager.getFee(swapParams);
        amountOut = amountOut > feeAmount ? amountOut - feeAmount : 0;

        if (amountOut < _minAmountOut) revert InsufficientOutputAmount(_minAmountOut, amountOut);

        require(IERC20(_tokenIn).transferFrom(tokenHolder, address(this), _amountIn));
        require(IERC20(_tokenOut).transfer(tokenHolder, amountOut));

        if (_tokenIn == token0) {
            reserveToken0 += _amountIn;
            reserveToken1 -= amountOut;
        } else {
            reserveToken1 += _amountIn;
            reserveToken0 -= amountOut;
        }

        emit Swap(_tokenIn, _tokenOut, _amountIn, amountOut);
    }
}
