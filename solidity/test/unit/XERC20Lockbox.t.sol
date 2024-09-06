// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {XERC20} from '../../contracts/XERC20.sol';
import {XERC20Lockbox} from '../../contracts/XERC20Lockbox.sol';
import {IXERC20Lockbox} from '../../interfaces/IXERC20Lockbox.sol';
import {IXERC20} from '../../interfaces/IXERC20.sol';

contract MockERC20NoDecimals {}

contract MockERC206Decimals is ERC20 {
  constructor() ERC20('MockERC206Decimals', 'ERC206') {}

  function decimals() public pure override returns (uint8) {
    return 6;
  }
}

contract MockERC2020Decimals is ERC20 {
  constructor() ERC20('MockERC2020Decimals', 'ERC2020') {}

  function decimals() public pure override returns (uint8) {
    return 20;
  }
}

abstract contract Base is Test {
  address internal _owner = vm.addr(1);
  uint256 internal _userPrivateKey = 0x1234;
  address internal _user = vm.addr(_userPrivateKey);
  address internal _minter = vm.addr(3);

  XERC20 internal _xerc20 = XERC20(vm.addr(4));
  IERC20 internal _erc20 = IERC20(vm.addr(5));

  event Deposit(address _sender, uint256 _amount);
  event Withdraw(address _sender, uint256 _amount);

  XERC20Lockbox internal _lockbox;
  XERC20Lockbox internal _nativeLockbox;

  address[] internal _bridges;
  uint256[] internal _limits;

  function setUp() public virtual {
    vm.mockCall(address(_erc20), abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(18));

    vm.startPrank(_owner);
    _nativeLockbox = new XERC20Lockbox(address(_xerc20), address(_erc20), true);
    _lockbox = new XERC20Lockbox(address(_xerc20), address(_erc20), false);
    vm.stopPrank();
  }
}

contract UnitDecimals is Base {
  function test_constructor_MaxDecimals() public {
    vm.mockCall(address(_erc20), abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(uint8(36) + 1));

    vm.expectRevert(IXERC20Lockbox.IXERC20Lockbox_MaxDecimals.selector);
    new XERC20Lockbox(address(_xerc20), address(_erc20), false);
  }

  function test_constructor_erc20Decimals_native() public {
    assertEq(_nativeLockbox.erc20Decimals(), 0);
  }

  function test_constructor_erc20Decimals_not_native_with_decimals(
    uint8 _erc20Decimals
  ) public {
    vm.assume(_erc20Decimals <= uint8(36));

    vm.mockCall(address(_erc20), abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(_erc20Decimals));

    _lockbox = new XERC20Lockbox(address(_xerc20), address(_erc20), false);

    assertEq(_lockbox.erc20Decimals(), _erc20Decimals);
  }

  function test_constructor_erc20Decimals_not_native_no_decimals() public {
    MockERC20NoDecimals erc20NoDecimals = new MockERC20NoDecimals();

    _lockbox = new XERC20Lockbox(address(_xerc20), address(erc20NoDecimals), false);

    assertEq(_lockbox.erc20Decimals(), 0);
  }
}

contract UnitDeposit is Base {
  function testDeposit(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.mockCall(
      address(_erc20),
      abi.encodeWithSelector(ERC20.transferFrom.selector, _owner, address(_lockbox), _amount),
      abi.encode(true)
    );
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.mint.selector, _owner, _amount), abi.encode(true));

    vm.expectCall(address(_xerc20), abi.encodeCall(XERC20.mint, (_owner, _amount)));
    vm.expectCall(address(_erc20), abi.encodeCall(ERC20.transferFrom, (_owner, address(_lockbox), _amount)));

    vm.prank(_owner);
    _lockbox.deposit(_amount);
  }

  function testDepositTo(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.mockCall(
      address(_erc20),
      abi.encodeWithSelector(IERC20.transferFrom.selector, _owner, address(_lockbox), _amount),
      abi.encode(true)
    );
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.mint.selector, _user, _amount), abi.encode(true));

    vm.expectCall(address(_xerc20), abi.encodeCall(XERC20.mint, (_user, _amount)));
    vm.expectCall(address(_erc20), abi.encodeCall(ERC20.transferFrom, (_owner, address(_lockbox), _amount)));

    vm.prank(_owner);
    _lockbox.depositTo(_user, _amount);
  }

  function testDepositEmitsEvent(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.mockCall(
      address(_erc20),
      abi.encodeWithSelector(IERC20.transferFrom.selector, _owner, address(_lockbox), _amount),
      abi.encode(true)
    );
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.mint.selector, _owner, _amount), abi.encode(true));

    vm.expectEmit(true, true, true, true);
    emit Deposit(_owner, _amount);
    vm.prank(_owner);
    _lockbox.deposit(_amount);
  }

  function testNonNativeIntoNativeDepositReverts(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.deal(_owner, _amount);
    vm.prank(_owner);
    vm.expectRevert(IXERC20Lockbox.IXERC20Lockbox_NotNative.selector);
    _lockbox.depositNative{value: _amount}();
  }

  function testNonNativeIntoNativeDeposittoReverts(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.deal(_owner, _amount);
    vm.prank(_owner);
    vm.expectRevert(IXERC20Lockbox.IXERC20Lockbox_NotNative.selector);
    _lockbox.depositNativeTo{value: _amount}(_user);
  }

  function testNativeRevertsIfDepositIntoNonNative(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.deal(_owner, _amount);
    vm.prank(_owner);
    vm.expectRevert(IXERC20Lockbox.IXERC20Lockbox_Native.selector);
    _nativeLockbox.deposit(_amount);
  }

  function testNativeRevertsIfDepositToIntoNonNative(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.deal(_owner, _amount);
    vm.prank(_owner);
    vm.expectRevert(IXERC20Lockbox.IXERC20Lockbox_Native.selector);
    _nativeLockbox.depositTo(_user, _amount);
  }

  function testNativeDeposit(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.deal(_owner, _amount);
    vm.prank(_owner);
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.mint.selector, _owner, _amount), abi.encode(true));

    vm.expectCall(address(_xerc20), abi.encodeCall(XERC20.mint, (_owner, _amount)));
    _nativeLockbox.depositNative{value: _amount}();
  }

  function testNativeDepositTo(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.deal(_owner, _amount);
    vm.prank(_owner);
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.mint.selector, _user, _amount), abi.encode(true));

    vm.expectCall(address(_xerc20), abi.encodeCall(XERC20.mint, (_user, _amount)));
    _nativeLockbox.depositNativeTo{value: _amount}(_user);
  }

  function testSendingNativeDepositByTransfer(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.deal(_owner, _amount);
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.mint.selector, _owner, _amount), abi.encode(true));

    vm.expectCall(address(_xerc20), abi.encodeCall(XERC20.mint, (_owner, _amount)));
    vm.prank(_owner);
    (bool _success,) = address(_nativeLockbox).call{value: _amount}('');
    assertEq(_success, true);
  }
}

contract UnitDepositLessDecimals is Base {
  uint256 decimalNormalizer = 10 ** 12;

  function setUp() public virtual override {
    _erc20 = IERC20(address(new MockERC206Decimals()));
    _xerc20 = new XERC20('Test', 'TST', _owner, 0, address(0), _owner, _bridges, _limits, _limits);

    vm.startPrank(_owner);
    _lockbox = new XERC20Lockbox(address(_xerc20), address(_erc20), false);
    _xerc20.setLockbox(address(_lockbox));
    vm.stopPrank();
  }

  function testDeposit(
    uint256 _amount
  ) public {
    vm.assume(_amount < type(uint192).max);
    uint256 _amountNormalized = _amount * decimalNormalizer;

    deal(address(_erc20), _user, _amount);

    vm.startPrank(_user);
    _erc20.approve(address(_lockbox), _amount);
    _lockbox.deposit(_amount);
    vm.stopPrank();

    assertEq(_xerc20.balanceOf(_user), _amountNormalized);
    assertEq(_erc20.balanceOf(_user), 0);
  }

  function testDepositTo(
    uint256 _amount
  ) public {
    vm.assume(_amount < type(uint192).max);
    uint256 _amountNormalized = _amount * decimalNormalizer;

    deal(address(_erc20), _user, _amount);

    vm.startPrank(_user);
    _erc20.approve(address(_lockbox), _amount);
    _lockbox.depositTo(_owner, _amount);
    vm.stopPrank();

    assertEq(_xerc20.balanceOf(_owner), _amountNormalized);
    assertEq(_erc20.balanceOf(_user), 0);
  }

  function testDepositRevertsAmountTooLarge() public {
    uint256 bigAmount = uint256(type(uint192).max) + 1;
    deal(address(_erc20), _user, bigAmount);

    vm.startPrank(_user);
    _erc20.approve(address(_lockbox), bigAmount);
    vm.expectRevert(IXERC20Lockbox.IXERC20Lockbox_AmountTooLarge.selector);
    _lockbox.depositTo(_owner, bigAmount);
    vm.stopPrank();
  }
}

contract UnitDepositMoreDecimals is Base {
  uint256 decimalNormalizer = 10 ** 2;

  function setUp() public virtual override {
    _erc20 = IERC20(address(new MockERC2020Decimals()));
    _xerc20 = new XERC20('Test', 'TST', _owner, 0, address(0), _owner, _bridges, _limits, _limits);

    vm.startPrank(_owner);
    _lockbox = new XERC20Lockbox(address(_xerc20), address(_erc20), false);
    _xerc20.setLockbox(address(_lockbox));
    vm.stopPrank();
  }

  function testDeposit(
    uint256 _amount
  ) public {
    vm.assume(_amount < type(uint192).max);
    uint256 _amountNormalized = _amount / decimalNormalizer;

    deal(address(_erc20), _user, _amount);

    vm.startPrank(_user);
    _erc20.approve(address(_lockbox), _amount);
    _lockbox.deposit(_amount);
    vm.stopPrank();

    assertEq(_xerc20.balanceOf(_user), _amountNormalized);
    assertEq(_erc20.balanceOf(_user), 0);
  }

  function testDepositTo(
    uint256 _amount
  ) public {
    vm.assume(_amount < type(uint192).max);
    uint256 _amountNormalized = _amount / decimalNormalizer;

    deal(address(_erc20), _user, _amount);

    vm.startPrank(_user);
    _erc20.approve(address(_lockbox), _amount);
    _lockbox.depositTo(_owner, _amount);
    vm.stopPrank();

    assertEq(_xerc20.balanceOf(_owner), _amountNormalized);
    assertEq(_erc20.balanceOf(_user), 0);
  }
}

contract UnitWithdraw is Base {
  function testWithdraw(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.burn.selector, _owner, _amount), abi.encode(true));
    vm.mockCall(address(_erc20), abi.encodeWithSelector(IERC20.transfer.selector, _owner, _amount), abi.encode(true));

    vm.expectCall(address(_xerc20), abi.encodeCall(XERC20.burn, (_owner, _amount)));
    vm.expectCall(address(_erc20), abi.encodeCall(ERC20.transfer, (_owner, _amount)));
    vm.prank(_owner);
    _lockbox.withdraw(_amount);
  }

  function testWithdrawEmitsEvent(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.burn.selector, _owner, _amount), abi.encode(true));
    vm.mockCall(address(_erc20), abi.encodeWithSelector(IERC20.transfer.selector, _owner, _amount), abi.encode(true));

    vm.expectEmit(true, true, true, true);
    emit Withdraw(_owner, _amount);
    vm.prank(_owner);
    _lockbox.withdraw(_amount);
  }

  function testNativeWithdraw(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.deal(_owner, _amount);

    vm.startPrank(_owner);
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.mint.selector, _owner, _amount), abi.encode(true));
    _nativeLockbox.depositNative{value: _amount}();
    _nativeLockbox.withdraw(_amount);
    vm.stopPrank();

    assertEq(_owner.balance, _amount);
  }

  function testNativeWithdrawTo(
    uint256 _amount
  ) public {
    vm.assume(_amount > 0);
    vm.deal(_owner, _amount);

    vm.startPrank(_owner);
    vm.mockCall(address(_xerc20), abi.encodeWithSelector(IXERC20.mint.selector, _owner, _amount), abi.encode(true));
    _nativeLockbox.depositNative{value: _amount}();
    _nativeLockbox.withdrawTo(_user, _amount);
    vm.stopPrank();

    assertEq(_user.balance, _amount);
  }
}

contract UnitWithdrawLessDecimals is Base {
  uint256 decimalNormalizer = 10 ** 12;

  function setUp() public virtual override {
    _erc20 = IERC20(address(new MockERC206Decimals()));
    _xerc20 = new XERC20('Test', 'TST', _owner, 0, address(0), _owner, _bridges, _limits, _limits);

    deal(address(_erc20), _owner, type(uint192).max);

    vm.startPrank(_owner);
    _lockbox = new XERC20Lockbox(address(_xerc20), address(_erc20), false);
    _xerc20.setLockbox(address(_lockbox));
    _erc20.approve(address(_lockbox), type(uint192).max);
    _lockbox.deposit(type(uint192).max);
    vm.stopPrank();
  }

  function testWithdraw(
    uint256 _amount
  ) public {
    vm.assume(_amount < type(uint192).max);
    uint256 amountNormalized = _amount / decimalNormalizer;

    vm.prank(_owner);
    _xerc20.transfer(_user, _amount);

    uint256 xer20BalanceBefore = _xerc20.balanceOf(_user);
    uint256 er20BalanceBefore = _erc20.balanceOf(_user);

    vm.startPrank(_user);
    _xerc20.approve(address(_lockbox), _amount);
    _lockbox.withdraw(_amount);
    vm.stopPrank();

    assertEq(_xerc20.balanceOf(_user), xer20BalanceBefore - _amount);
    assertEq(_erc20.balanceOf(_user), er20BalanceBefore + amountNormalized);
  }
}

contract UnitWithdrawMoreDecimals is Base {
  uint256 decimalNormalizer = 10 ** 2;

  function setUp() public virtual override {
    _erc20 = IERC20(address(new MockERC2020Decimals()));
    _xerc20 = new XERC20('Test', 'TST', _owner, 0, address(0), _owner, _bridges, _limits, _limits);

    deal(address(_erc20), _owner, type(uint256).max);

    vm.startPrank(_owner);
    _lockbox = new XERC20Lockbox(address(_xerc20), address(_erc20), false);
    _xerc20.setLockbox(address(_lockbox));
    _erc20.approve(address(_lockbox), type(uint256).max);
    _lockbox.deposit(type(uint256).max);
    vm.stopPrank();
  }

  function testWithdraw(
    uint256 _amount
  ) public {
    vm.assume(_amount < type(uint192).max);
    uint256 amountNormalized = _amount * decimalNormalizer;

    vm.prank(_owner);
    _xerc20.transfer(_user, _amount);

    uint256 xer20BalanceBefore = _xerc20.balanceOf(_user);
    uint256 er20BalanceBefore = _erc20.balanceOf(_user);

    vm.startPrank(_user);
    _xerc20.approve(address(_lockbox), _amount);
    _lockbox.withdraw(_amount);
    vm.stopPrank();

    assertEq(_xerc20.balanceOf(_user), xer20BalanceBefore - _amount);
    assertEq(_erc20.balanceOf(_user), er20BalanceBefore + amountNormalized);
  }
}
