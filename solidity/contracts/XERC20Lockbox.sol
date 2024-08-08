// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {IXERC20} from '../interfaces/IXERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IXERC20Lockbox} from '../interfaces/IXERC20Lockbox.sol';

contract XERC20Lockbox is IXERC20Lockbox {
  using SafeERC20 for IERC20;
  using SafeCast for uint256;

  /**
   * @notice The XERC20 token of this contract
   */
  IXERC20 public immutable XERC20;

  /**
   * @notice The ERC20 token of this contract
   */
  IERC20 public immutable ERC20;

  /**
   * @notice Whether the ERC20 token is the native gas token of this chain
   */
  bool public immutable IS_NATIVE;

  /**
   * @notice The ERC20 decimals, assumed to be 0 if the token does not have a decimals() method
   */
  uint8 public erc20Decimals;

  /// @dev If nativeTokenDecimals is different than 18 decimals, bridge will inflate or deflate token amounts
  ///      when depositing to child chain to match 18 decimal denomination. Opposite process happens when
  ///      amount is withdrawn back to parent chain. In order to avoid uint256 overflows we restrict max number
  ///      of decimals to 36 which should be enough for most practical use-cases.
  uint8 constant MAX_DECIMALS = uint8(36);

  /// @dev Max amount of erc20 native token that can deposit when upscaling is required (i.e. < 18 decimals)
  ///      Amounts higher than this would risk uint256 overflows when adjusting decimals. Considering
  ///      18 decimals are 60 bits, we choose 2^192 as the limit which equals to ~6.3*10^57 weis of token
  uint256 constant MAX_UPSCALE_AMOUNT = type(uint192).max;

  /**
   * @notice Constructor
   *
   * @param _xerc20 The address of the XERC20 contract
   * @param _erc20 The address of the ERC20 contract
   * @param _isNative Whether the ERC20 token is the native gas token of this chain or not
   */
  constructor(address _xerc20, address _erc20, bool _isNative) {
    XERC20 = IXERC20(_xerc20);
    ERC20 = IERC20(_erc20);
    IS_NATIVE = _isNative;

    if (!_isNative) {
      try IERC20Metadata(_erc20).decimals() returns (uint8 decimals) {
        if (decimals > MAX_DECIMALS) {
          revert IXERC20Lockbox_MaxDecimals();
        }
        erc20Decimals = decimals;
      } catch {
        erc20Decimals = 0;
      }
    }
  }

  /**
   * @notice Deposit native tokens into the lockbox
   */
  function depositNative() public payable {
    if (!IS_NATIVE) revert IXERC20Lockbox_NotNative();

    _deposit(msg.sender, msg.value);
  }

  /**
   * @notice Deposit ERC20 tokens into the lockbox
   *
   * @param _amount The amount of tokens to deposit
   */
  function deposit(uint256 _amount) external {
    if (IS_NATIVE) revert IXERC20Lockbox_Native();

    _deposit(msg.sender, _amount);
  }

  /**
   * @notice Deposit ERC20 tokens into the lockbox, and send the XERC20 to a user
   *
   * @param _to The user to send the XERC20 to
   * @param _amount The amount of tokens to deposit
   */
  function depositTo(address _to, uint256 _amount) external {
    if (IS_NATIVE) revert IXERC20Lockbox_Native();

    _deposit(_to, _amount);
  }

  /**
   * @notice Deposit the native asset into the lockbox, and send the XERC20 to a user
   *
   * @param _to The user to send the XERC20 to
   */
  function depositNativeTo(address _to) public payable {
    if (!IS_NATIVE) revert IXERC20Lockbox_NotNative();

    _deposit(_to, msg.value);
  }

  /**
   * @notice Withdraw ERC20 tokens from the lockbox
   *
   * @param _amount The amount of tokens to withdraw
   */
  function withdraw(uint256 _amount) external {
    _withdraw(msg.sender, _amount);
  }

  /**
   * @notice Withdraw tokens from the lockbox
   *
   * @param _to The user to withdraw to
   * @param _amount The amount of tokens to withdraw, this amount has to match ERC20 token's granularity, otherwise it
   * will be rounded down
   */
  function withdrawTo(address _to, uint256 _amount) external {
    _withdraw(_to, _amount);
  }

  /**
   * @notice Withdraw tokens from the lockbox
   *
   * @param _to The user to withdraw to
   * @param _amount The amount of tokens to withdraw, this amount has to match ERC20 token's granularity, otherwise it
   * will be rounded down
   */
  function _withdraw(address _to, uint256 _amount) internal {
    emit Withdraw(_to, _amount);

    XERC20.burn(msg.sender, _amount);

    if (IS_NATIVE) {
      (bool _success,) = payable(_to).call{value: _amount}('');
      if (!_success) revert IXERC20Lockbox_WithdrawFailed();
    } else {
      // If ERC20 token uses number of decimals other than 18 then the amount should be normalized from 18.
      ERC20.safeTransfer(_to, _normalizeAmount(_amount, 18, erc20Decimals));
    }
  }

  /**
   * @notice Deposit tokens into the lockbox
   *
   * @param _to The address to send the XERC20 to
   * @param _amount The amount of tokens to deposit
   */
  function _deposit(address _to, uint256 _amount) internal {
    uint256 normalizedAmount = _amount;

    if (!IS_NATIVE) {
      ERC20.safeTransferFrom(msg.sender, address(this), _amount);

      // If ERC20 token uses number of decimals other than 18 then the amount should be normalized to 18.
      // Make sure that normalized amount will not overflow uint256
      if (erc20Decimals < 18 && _amount > MAX_UPSCALE_AMOUNT) {
        revert IXERC20Lockbox_AmountTooLarge();
      }

      normalizedAmount = _normalizeAmount(_amount, erc20Decimals, 18);
    }

    XERC20.mint(_to, normalizedAmount);
    emit Deposit(_to, _amount);
  }

  /**
   * @notice Normalize amount from one decimal denomination to another
   * @dev Ie. let's say amount is 752. If ERC20 has 16 decimals and is being adjusted to
   *     18 decimals then amount will be 75200. If token has 20 decimals adjusted amount
   *     is 7. If token uses no decimals converted amount is 752*10^18.
   *     When amount is adjusted from 18 decimals back to native token decimals, opposite
   *     process is performed.
   * @param _amount amount to convert
   * @param _decimalsIn current decimals
   * @param _decimalsOut target decimals
   * @return amount converted to 'decimalsOut' decimals
   */
  function _normalizeAmount(uint256 _amount, uint8 _decimalsIn, uint8 _decimalsOut) internal pure returns (uint256) {
    uint256 normalizedAmount = _amount;

    if (_decimalsIn < _decimalsOut) {
      normalizedAmount = _amount * 10 ** (_decimalsOut - _decimalsIn);
    } else {
      normalizedAmount = _amount / 10 ** (_decimalsIn - _decimalsOut);
    }

    return normalizedAmount;
  }

  /**
   * @notice Fallback function to deposit native tokens
   */
  receive() external payable {
    depositNative();
  }
}
