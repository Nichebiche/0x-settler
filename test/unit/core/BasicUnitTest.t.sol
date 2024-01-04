// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Basic} from "../../../src/core/Basic.sol";
import {Permit2Payment} from "../../../src/core/Permit2Payment.sol";

import {IERC20} from "../../../src/IERC20.sol";
import {Utils} from "../Utils.sol";

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract BasicDummy is Basic, Permit2Payment {
    constructor(address permit2, address feeRecipient, address allowanceHolder)
        Permit2Payment(permit2, feeRecipient, allowanceHolder)
    {}

    function sellToPool(address pool, IERC20 sellToken, uint256 bips, uint256 offset, bytes memory data) public {
        super.basicSellToPool(pool, sellToken, bips, offset, data);
    }
}

contract BasicUnitTest is Utils, Test {
    BasicDummy basic;
    address PERMIT2 = _deterministicAddress("PERMIT2");
    address FEE_RECIPIENT = _deterministicAddress("FEE_RECIPIENT");
    address ALLOWANCE_HOLDER = _deterministicAddress("ALLOWANCE_HOLDER");
    address POOL = _createNamedRejectionDummy("POOL");
    IERC20 TOKEN = IERC20(_createNamedRejectionDummy("TOKEN"));

    function setUp() public {
        basic = new BasicDummy(PERMIT2, FEE_RECIPIENT, ALLOWANCE_HOLDER);
    }

    function testBasicSell() public {
        uint256 bips = 10_000;
        uint256 offset = 4;
        uint256 amount = 99999;
        bytes4 selector = bytes4(hex"12345678");
        bytes memory data = abi.encodePacked(selector, amount);

        _mockExpectCall(
            address(TOKEN), abi.encodeWithSelector(IERC20.balanceOf.selector, address(basic)), abi.encode(amount)
        );
        _mockExpectCall(
            address(TOKEN),
            abi.encodeWithSelector(IERC20.allowance.selector, address(basic), address(POOL)),
            abi.encode(amount)
        );

        _mockExpectCall(address(POOL), data, abi.encode(true));

        basic.sellToPool(POOL, TOKEN, bips, offset, data);
    }

    /// @dev adjust the balange of the contract to be less than expected
    function testBasicSellLowerBalanceAmount() public {
        uint256 bips = 10_000;
        uint256 offset = 4;
        uint256 amount = 99999;
        bytes4 selector = bytes4(hex"12345678");
        bytes memory data = abi.encodePacked(selector, amount);

        _mockExpectCall(
            address(TOKEN), abi.encodeWithSelector(IERC20.balanceOf.selector, address(basic)), abi.encode(amount / 2)
        );
        _mockExpectCall(
            address(TOKEN),
            abi.encodeWithSelector(IERC20.allowance.selector, address(basic), address(POOL)),
            abi.encode(amount)
        );

        _mockExpectCall(address(POOL), abi.encodePacked(selector, amount / 2), abi.encode(true));
        basic.sellToPool(POOL, TOKEN, bips, offset, data);
    }

    /// @dev adjust the balange of the contract to be greater than expected
    function testBasicSellGreaterBalanceAmount() public {
        uint256 bips = 10_000;
        uint256 offset = 4;
        uint256 amount = 99999;
        bytes4 selector = bytes4(hex"12345678");
        bytes memory data = abi.encodePacked(selector, amount);

        _mockExpectCall(
            address(TOKEN), abi.encodeWithSelector(IERC20.balanceOf.selector, address(basic)), abi.encode(amount * 2)
        );
        _mockExpectCall(
            address(TOKEN),
            abi.encodeWithSelector(IERC20.allowance.selector, address(basic), address(POOL)),
            abi.encode(amount * 2)
        );

        _mockExpectCall(address(POOL), abi.encodePacked(selector, amount * 2), abi.encode(true));
        basic.sellToPool(POOL, TOKEN, bips, offset, data);
    }
}
