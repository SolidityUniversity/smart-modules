pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ISwap.sol";
import "./FeeManager.sol";
import "./EIP712Swap.sol";

contract LiquidityPool is ISwap, FeeManager {
  address public token0;
  uint256 public token0Decimals;
  address public token1;
  uint256 public token1Decimals;
  uint256 public reserveToken0;
  uint256 public reserveToken1;
  FeeManager public feeManager;
  EIP712Swap public eip712Swap;

  // @notice Emitted when liquidity is added to the pool
  /// @param _token The token that was added
  /// @param _amount The amount of tokens that were added
  event LiquidityAdded(address indexed _token, uint256 _amount);

  // @notice Emitted when a swap is executed
  /// @param _tokenIn The token that was swapped in
  /// @param _tokenOut The token that was swapped out
  /// @param _amountIn The amount of tokens that were swapped in
  /// @param _amountOut The amount of tokens that were swapped out
  event Swap(address indexed _tokenIn, address indexed _tokenOut, uint256 _amountIn, uint256 _amountOut);

  error InsufficientTokenBalance();
  error InvalidTokenAddress(address _token);
  error InvalidTokenPair(address _tokenIn, address _tokenOut);
  error InsufficientLiquidity();
  error InsufficientOutputAmount(uint256 expected, uint256 actual);
  error ExcessiveInputAmount(uint256 expected, uint256 actual);
  error InsufficientAllowance();

  constructor(address _token0, uint256 _token0Decimals, address _token1, uint256 _token1Decimals, address _feeManager, address _eip712Swap) {
    token0 = _token0;
    token0Decimals = _token0Decimals;
    token1 = _token1;
    token1Decimals = _token1Decimals;
    feeManager = FeeManager(_feeManager);
    eip712Swap = EIP712Swap(_eip712Swap);
  }

  // @notice Add liquidity to the pool
  /// @param _token The token to add liquidity for
  /// @param _amount The amount of tokens to add
  function addLiquidity(address _token, uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_token == token0 || _token == token1) {
      revert InvalidTokenAddress(_token);
    }

    if (IERC20(_token).balanceOf(address(msg.sender)) < _amount) {
      revert InsufficientTokenBalance();
    }

    require(IERC20(_token).transferFrom(msg.sender, address(this), _amount));

    if (_token == token0) {
      reserveToken0 += _amount;
    } else if (_token == token1) {
      reserveToken1 += _amount;
    }

    emit LiquidityAdded(_token, _amount);
  }

  // @notice Get the reserves of the pool
  /// @return _reserveToken0 The reserve of token0
  /// @return _reserveToken1 The reserve of token1
  function getReserves() external view returns (uint256 _reserveToken0, uint256 _reserveToken1) {
    _reserveToken0 = reserveToken0;
    _reserveToken1 = reserveToken1;
  }

  /// @notice Get the price of the token in the pool
  /// @param _tokenIn The token to get the price of
  /// @param _tokenOut The token to get the price of
  /// @return _price The price of the token in the pool
  function getPrice(address _tokenIn, address _tokenOut) external view returns (uint256 _price) {
    uint256 _reserveTokenIn = _tokenIn == token0 ? reserveToken0 : reserveToken1;
    uint256 _reserveTokenOut = _tokenOut == token0 ? reserveToken0 : reserveToken1;
    uint256 _tokenInDecimals = _tokenIn == token0 ? token0Decimals : token1Decimals;
    uint256 _tokenOutDecimals = _tokenOut == token0 ? token0Decimals : token1Decimals;

    _price = (_reserveTokenIn * 10 ** _tokenInDecimals) / (_reserveTokenOut * 10 ** _tokenOutDecimals);
  }

  /// @notice Swap tokens in the pool
  /// @param _sender The address of the sender
  /// @param _tokenIn The token to swap in
  /// @param _tokenOut The token to swap out
  /// @param _amountIn The amount of tokens to swap in
  /// @param _minAmountOut The minimum amount of tokens to swap out
  function swap(
    address _sender,
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint256 _minAmountOut
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_tokenIn != token0 && _tokenIn != token1 || _tokenOut != token0 && _tokenOut != token1 || _tokenIn == _tokenOut) {
      revert InvalidTokenPair(_tokenIn, _tokenOut);
    }

    address _msgSender = msg.sender == address(eip712Swap) ? _sender : msg.sender;

    if (IERC20(_tokenIn).allowance(_msgSender, address(this)) < _amountIn) revert InsufficientAllowance();

    uint256 _reserveTokenIn = _tokenIn == token0 ? reserveToken0 : reserveToken1;
    uint256 _reserveTokenOut = _tokenOut == token0 ? reserveToken0 : reserveToken1;
    uint256 _tokenInDecimals = _tokenIn == token0 ? token0Decimals : token1Decimals;
    uint256 _tokenOutDecimals = _tokenOut == token0 ? token0Decimals : token1Decimals;

    uint256 amountOut = (_amountIn * (10 ** _tokenOutDecimals) * _reserveTokenOut) / (_reserveTokenIn + _amountIn * (10 ** _tokenOutDecimals));
    uint256 _fee = feeManager.getFee(SwapParams(_tokenIn, _tokenOut, _amountIn, _reserveTokenIn, _reserveTokenOut));
    amountOut -= (_fee * (10 ** _tokenOutDecimals)) / (10 ** _tokenInDecimals);

    if (amountOut < _minAmountOut) revert InsufficientOutputAmount(_minAmountOut, amountOut);
    if (amountOut > _reserveTokenOut) revert InsufficientLiquidity();

    require(IERC20(_tokenIn).transferFrom(_msgSender, address(this), _amountIn));
    require(IERC20(_tokenOut).transfer(_msgSender, amountOut));

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