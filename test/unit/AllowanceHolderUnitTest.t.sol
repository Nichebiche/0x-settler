// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {AllowanceHolder} from "../../src/AllowanceHolder.sol";
import {IAllowanceHolder} from "../../src/IAllowanceHolder.sol";

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IERC20} from "../../src/IERC20.sol";

import {Utils} from "./Utils.sol";

import {Test} from "forge-std/Test.sol";

contract AllowanceHolderDummy is AllowanceHolder {
    function getAllowed(address operator, address owner, address token) external view returns (uint256 r) {
        return _getAllowed(operator, owner, token);
    }

    function setAllowed(address operator, address owner, address token, uint256 allowed) external {
        return _setAllowed(operator, owner, token, allowed);
    }
}

contract AllowanceHolderUnitTest is Utils, Test {
    AllowanceHolderDummy ah;
    address OPERATOR = _createNamedRejectionDummy("OPERATOR");
    address TOKEN = _createNamedRejectionDummy("TOKEN");
    address OWNER = address(this);
    address RECIPIENT = _createNamedRejectionDummy("RECIPIENT");
    uint256 AMOUNT = 123456;

    function setUp() public {
        ah = new AllowanceHolderDummy();
    }

    function testPermitSetGet() public {
        ah.setAllowed(OPERATOR, OWNER, TOKEN, 123456);
        assertEq(ah.getAllowed(OPERATOR, OWNER, TOKEN), 123456);
    }

    function testPermitAuthorised() public {
        IAllowanceHolder.TransferDetails[] memory transferDetails = new IAllowanceHolder.TransferDetails[](1);
        transferDetails[0] = IAllowanceHolder.TransferDetails({token: TOKEN, recipient: RECIPIENT, amount: AMOUNT});

        ah.setAllowed(OPERATOR, OWNER, TOKEN, AMOUNT);
        assertEq(ah.getAllowed(OPERATOR, OWNER, TOKEN), AMOUNT);

        _mockExpectCall(
            TOKEN, abi.encodeWithSelector(IERC20.transferFrom.selector, OWNER, RECIPIENT, AMOUNT), new bytes(0)
        );
        vm.prank(OPERATOR);
        assertTrue(ah.holderTransferFrom(OWNER, transferDetails));

        assertEq(ah.getAllowed(OPERATOR, OWNER, TOKEN), 0);
    }

    function testPermitAuthorisedMultipleConsumption() public {
        IAllowanceHolder.TransferDetails[] memory transferDetails = new IAllowanceHolder.TransferDetails[](1);

        // Note: we use amount / 2 (+ / - 1) to register multiple mocks
        transferDetails[0] =
            IAllowanceHolder.TransferDetails({token: TOKEN, recipient: RECIPIENT, amount: (AMOUNT / 2) + 1});

        ah.setAllowed(OPERATOR, OWNER, TOKEN, AMOUNT);
        assertEq(ah.getAllowed(OPERATOR, OWNER, TOKEN), AMOUNT);
        _mockExpectCall(
            TOKEN,
            abi.encodeWithSelector(IERC20.transferFrom.selector, OWNER, RECIPIENT, (AMOUNT / 2) + 1),
            new bytes(0)
        );
        vm.prank(OPERATOR);
        assertTrue(ah.holderTransferFrom(OWNER, transferDetails));
        assertEq(ah.getAllowed(OPERATOR, OWNER, TOKEN), (AMOUNT / 2) - 1);

        _mockExpectCall(
            TOKEN,
            abi.encodeWithSelector(IERC20.transferFrom.selector, OWNER, RECIPIENT, (AMOUNT / 2) - 1),
            new bytes(0)
        );
        transferDetails[0] =
            IAllowanceHolder.TransferDetails({token: TOKEN, recipient: RECIPIENT, amount: (AMOUNT / 2) - 1});
        vm.prank(OPERATOR);
        assertTrue(ah.holderTransferFrom(OWNER, transferDetails));

        assertEq(ah.getAllowed(OPERATOR, OWNER, TOKEN), 0);
    }

    function testPermitUnauthorisedOperator() public {
        IAllowanceHolder.TransferDetails[] memory transferDetails = new IAllowanceHolder.TransferDetails[](1);
        transferDetails[0] = IAllowanceHolder.TransferDetails({token: TOKEN, recipient: RECIPIENT, amount: AMOUNT});

        ah.setAllowed(OPERATOR, OWNER, TOKEN, AMOUNT);
        vm.expectRevert();
        ah.holderTransferFrom(OWNER, transferDetails);
    }

    function testPermitUnauthorisedAmount() public {
        IAllowanceHolder.TransferDetails[] memory transferDetails = new IAllowanceHolder.TransferDetails[](1);
        transferDetails[0] = IAllowanceHolder.TransferDetails({token: TOKEN, recipient: RECIPIENT, amount: AMOUNT + 1});

        ah.setAllowed(OPERATOR, OWNER, TOKEN, AMOUNT);
        vm.expectRevert();
        vm.prank(OPERATOR);
        ah.holderTransferFrom(OWNER, transferDetails);
    }

    function testPermitUnauthorisedToken() public {
        IAllowanceHolder.TransferDetails[] memory transferDetails = new IAllowanceHolder.TransferDetails[](1);
        transferDetails[0] = IAllowanceHolder.TransferDetails({token: TOKEN, recipient: RECIPIENT, amount: AMOUNT});

        ah.setAllowed(OPERATOR, OWNER, address(0xdead), AMOUNT);
        vm.expectRevert();
        ah.holderTransferFrom(OWNER, transferDetails);
    }

    function testPermitAuthorisedStorageKey() public {
        vm.record();
        ah.setAllowed(OPERATOR, OWNER, TOKEN, AMOUNT);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(ah));

        // Authorisation key is calculated as packed encoded keccak(operator, owner, token)
        bytes32 key = keccak256(abi.encodePacked(OPERATOR, OWNER, TOKEN));
        assertEq(reads.length, 1);
        assertEq(writes.length, 1);
        assertEq(reads[0], key);
        assertEq(writes[0], key);

        ah.getAllowed(OPERATOR, OWNER, TOKEN);
        (reads, writes) = vm.accesses(address(ah));
        assertEq(reads.length, 2);
        assertEq(writes.length, 1);
        assertEq(reads[1], key);
    }

    function testPermitExecute() public {
        address target = _createNamedRejectionDummy("TARGET");
        address operator = target;
        uint256 value = 999;

        ISignatureTransfer.TokenPermissions[] memory permits = new ISignatureTransfer.TokenPermissions[](1);
        permits[0] = ISignatureTransfer.TokenPermissions({token: TOKEN, amount: AMOUNT});
        bytes memory data = hex"deadbeef";

        _mockExpectCall(address(target), abi.encodePacked(data, address(this)), abi.encode(true));
        ah.execute{value: value}(operator, permits, payable(target), data);
    }
}
