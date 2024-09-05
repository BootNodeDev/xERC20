// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {XERC20} from '../contracts/XERC20.sol';
import {IXERC20Factory} from '../interfaces/IXERC20Factory.sol';
import {XERC20Lockbox} from '../contracts/XERC20Lockbox.sol';
import {CREATE3} from 'isolmate/utils/CREATE3.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

contract XERC20Factory is IXERC20Factory {
  using EnumerableSet for EnumerableSet.AddressSet;

  /**
   * @notice Address of the xerc20 maps to the address of its lockbox if it has one
   */
  mapping(address => address) internal _lockboxRegistry;

  /**
   * @notice The set of registered lockboxes
   */
  EnumerableSet.AddressSet internal _lockboxRegistryArray;

  /**
   * @notice The set of registered XERC20 tokens
   */
  EnumerableSet.AddressSet internal _xerc20RegistryArray;

  /**
   * @notice Deploys an XERC20 contract using CREATE3
   * @dev _limits and _minters must be the same length
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _decimals The number of decimals used to get its user representation
   * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of bridges that you are adding (optional, can be an empty array)
   * @param _initialSupply The initial supply of the token
   * @param _receiver The initial supply receiver
   * @param _owner The owner of the token, zero address if the owner is the sender
   * @return _xerc20 The address of the xerc20
   */
  function deployXERC20(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    uint256 _initialSupply,
    address _receiver,
    address _owner
  ) external returns (address _xerc20) {
    _xerc20 = _deployXERC20(
      _name, _symbol, _decimals, _minterLimits, _burnerLimits, _bridges, _initialSupply, _receiver, _owner
    );
  }

  /**
   * @notice Deploys an XERC20Lockbox contract using CREATE3
   *
   * @dev When deploying a lockbox for the gas token of the chain, then, the base token needs to be address(0)
   * @param _xerc20 The address of the xerc20 that you want to deploy a lockbox for
   * @param _baseToken The address of the base token that you want to lock
   * @param _isNative Whether or not the base token is the native (gas) token of the chain. Eg: MATIC for polygon chain
   * @return _lockbox The address of the lockbox
   */
  function deployLockbox(
    address _xerc20,
    address _baseToken,
    bool _isNative
  ) external returns (address payable _lockbox) {
    if ((_baseToken == address(0) && !_isNative) || (_isNative && _baseToken != address(0)) || (_xerc20 == address(0)))
    {
      revert IXERC20Factory_BadTokenAddress();
    }

    uint8 baseTokenDecimals = 18;
    uint8 xerc20TokenDecimals;
    if (!_isNative) {
      try IERC20Metadata(_baseToken).decimals() returns (uint8 decimals) {
        baseTokenDecimals = decimals;
      } catch {
        baseTokenDecimals = 0;
      }
    }

    try IERC20Metadata(_xerc20).decimals() returns (uint8 decimals) {
      xerc20TokenDecimals = decimals;
    } catch {
      xerc20TokenDecimals = 0;
    }

    if (baseTokenDecimals != xerc20TokenDecimals) revert IXERC20Factory_IncompatibleDecimals();

    _lockbox = _deployLockbox(_xerc20, _baseToken, _isNative);
  }

  /**
   * @notice Deploys an XERC20 contract using CREATE3 and Deploys an XERC20Lockbox contract using CREATE3
   * @dev _limits and _minters must be the same length
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _baseToken The address of the base token that you want to lock
   * @param _isNative Whether or not the base token is the native (gas) token of the chain. Eg: MATIC for polygon chain
   * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of bridges that you are adding (optional, can be an empty array)
   * @param _owner The owner of the token, zero address if the owner is the sender
   * @return _xerc20 The addresses of the xerc20
   * @return _lockbox The addresses of the lockbox
   */
  function deployXERC20AndLockbox(
    string memory _name,
    string memory _symbol,
    address _baseToken,
    bool _isNative,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    address _owner
  ) external returns (address _xerc20, address payable _lockbox) {
    if ((_baseToken == address(0) && !_isNative) || (_isNative && _baseToken != address(0))) {
      revert IXERC20Factory_BadTokenAddress();
    }

    uint8 baseTokenDecimals;
    if (_isNative) {
      baseTokenDecimals = 18;
    } else {
      try IERC20Metadata(_baseToken).decimals() returns (uint8 decimals) {
        baseTokenDecimals = decimals;
      } catch {
        baseTokenDecimals = 0;
      }
    }

    _xerc20 =
      _deployXERC20(_name, _symbol, baseTokenDecimals, _minterLimits, _burnerLimits, _bridges, 0, address(0), _owner);

    _lockbox = _deployLockbox(_xerc20, _baseToken, _isNative);
  }

  /**
   * @notice Deploys an XERC20 contract using CREATE3
   * @dev _limits and _minters must be the same length
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _decimals The number of decimals used to get its user representation
   * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of burners that you are adding (optional, can be an empty array)
   * @param _initialSupply The initial supply of the token
   * @param _receiver The initial supply receiver, zero address if the receiver is the sender
   * @param _owner The owner of the token, zero address if the owner is the sender
   * @return _xerc20 The address of the xerc20
   */
  function _deployXERC20(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    uint256 _initialSupply,
    address _receiver,
    address _owner
  ) internal returns (address _xerc20) {
    uint256 _bridgesLength = _bridges.length;
    if (_minterLimits.length != _bridgesLength || _burnerLimits.length != _bridgesLength) {
      revert IXERC20Factory_InvalidLength();
    }

    if (_initialSupply > 0 && _receiver == address(0)) {
      _receiver = msg.sender;
    }

    _owner = _owner != address(0) ? _owner : msg.sender;

    bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));
    bytes memory _creation = type(XERC20).creationCode;
    bytes memory _bytecode = abi.encodePacked(
      _creation,
      abi.encode(
        _name,
        _symbol,
        _decimals,
        address(this),
        _initialSupply,
        _receiver,
        _owner,
        _bridges,
        _minterLimits,
        _burnerLimits
      )
    );

    _xerc20 = CREATE3.deploy(_salt, _bytecode, 0);

    EnumerableSet.add(_xerc20RegistryArray, _xerc20);

    emit XERC20Deployed(_xerc20);
  }

  /**
   * @notice Deploys an XERC20Lockbox contract using CREATE3
   *
   * @dev When deploying a lockbox for the gas token of the chain, then, the base token needs to be address(0)
   * @param _xerc20 The address of the xerc20 that you want to deploy a lockbox for
   * @param _baseToken The address of the base token that you want to lock
   * @param _isNative Whether or not the base token is the native (gas) token of the chain. Eg: MATIC for polygon chain
   * @return _lockbox The address of the lockbox
   */
  function _deployLockbox(
    address _xerc20,
    address _baseToken,
    bool _isNative
  ) internal returns (address payable _lockbox) {
    if (XERC20(_xerc20).owner() != msg.sender) revert IXERC20Factory_NotOwner();
    if (_lockboxRegistry[_xerc20] != address(0)) revert IXERC20Factory_LockboxAlreadyDeployed();

    bytes32 _salt = keccak256(abi.encodePacked(_xerc20, _baseToken, msg.sender));
    bytes memory _creation = type(XERC20Lockbox).creationCode;
    bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(_xerc20, _baseToken, _isNative));

    _lockbox = payable(CREATE3.deploy(_salt, _bytecode, 0));

    XERC20(_xerc20).setLockbox(address(_lockbox));
    EnumerableSet.add(_lockboxRegistryArray, _lockbox);
    _lockboxRegistry[_xerc20] = _lockbox;

    emit LockboxDeployed(_lockbox);
  }
}
