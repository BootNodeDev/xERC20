// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {XERC20Factory} from '../contracts/XERC20Factory.sol';
import {EnumerableSet} from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import {XERC20Upgradeable} from '../contracts/XERC20Upgradeable.sol';
import {CREATE3} from 'isolmate/utils/CREATE3.sol';
import {ProxyAdmin} from '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol';
import {TransparentUpgradeableProxy} from '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

contract XERC20UpgradeableFactory is XERC20Factory {
  address public immutable implementation;

  /**
   * @notice Emitted when a new XERC20 is deployed
   *
   * @param _xerc20 The address of the xerc20
   * @param _admin The address of the ProxyAdmin contract
   */
  event XERC20Deployed(address _xerc20, address _admin);

  constructor() {
    implementation = address(new XERC20Upgradeable());
  }

  /**
   * @notice Deploys an XERC20 contract using CREATE3
   * @dev _limits and _minters must be the same length
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of bridges that you are adding (optional, can be an empty array)
   * @param _initialSupply The initial supply of the token
   * @param _owner The owner of the token, zero address if the owner is the sender
   * @return _xerc20 The address of the xerc20
   * @return _admin The address of the ProxyAdmin contract
   */
  function deployXERC20Upgradeable(
    string memory _name,
    string memory _symbol,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    uint256 _initialSupply,
    address _owner
  ) external returns (address _xerc20, address _admin) {
    (_xerc20, _admin) =
      _deployXERC20Upgradeable(_name, _symbol, _minterLimits, _burnerLimits, _bridges, _initialSupply, _owner);

    emit XERC20Deployed(_xerc20, _admin);
  }

  /**
   * @notice Deploys an XERC20 contract using CREATE3
   * @dev _limits and _minters must be the same length
   * @param _name The name of the token
   * @param _symbol The symbol of the token
   * @param _minterLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _burnerLimits The array of limits that you are adding (optional, can be an empty array)
   * @param _bridges The array of burners that you are adding (optional, can be an empty array)
   * @param _initialSupply The initial supply of the token
   * @param _owner The owner of the token, zero address if the owner is the sender
   * @return _xerc20 The address of the xerc20
   * @return _admin The address of the ProxyAdmin contract
   */
  function _deployXERC20Upgradeable(
    string memory _name,
    string memory _symbol,
    uint256[] memory _minterLimits,
    uint256[] memory _burnerLimits,
    address[] memory _bridges,
    uint256 _initialSupply,
    address _owner
  ) internal returns (address _xerc20, address _admin) {
    uint256 _bridgesLength = _bridges.length;
    if (_minterLimits.length != _bridgesLength || _burnerLimits.length != _bridgesLength) {
      revert IXERC20Factory_InvalidLength();
    }

    _admin = address(new ProxyAdmin());
    ProxyAdmin(_admin).transferOwnership(_owner != address(0) ? _owner : msg.sender);

    bytes memory initialize =
      abi.encodeWithSelector(XERC20Upgradeable.initialize.selector, _name, _symbol, address(this), _initialSupply);

    bytes32 _salt = keccak256(abi.encodePacked(_name, _symbol, msg.sender));
    bytes memory _creation = type(TransparentUpgradeableProxy).creationCode;
    bytes memory _bytecode = abi.encodePacked(_creation, abi.encode(implementation, _admin, initialize));

    _xerc20 = CREATE3.deploy(_salt, _bytecode, 0);

    EnumerableSet.add(_xerc20RegistryArray, _xerc20);

    for (uint256 _i; _i < _bridgesLength; ++_i) {
      XERC20Upgradeable(_xerc20).setLimits(_bridges[_i], _minterLimits[_i], _burnerLimits[_i]);
    }

    if (_initialSupply > 0) {
      XERC20Upgradeable(_xerc20).transfer(msg.sender, _initialSupply);
    }

    XERC20Upgradeable(_xerc20).transferOwnership(_owner != address(0) ? _owner : msg.sender);
  }
}
