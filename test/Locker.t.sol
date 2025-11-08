// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Setup } from "test/utils/Setup.sol";
import { Locker } from "src/Locker.sol";
import { Operator } from "src/Operator.sol";
import { MockTarget } from "test/mocks/MockTarget.sol";

contract LockerTest is Setup {
    MockTarget public target;

    address public user = address(0x3);

    event OperatorUpdated(address operator);
    event Executed(address indexed caller, address indexed to);

    function setUp() public override {
        super.setUp();
        target = new MockTarget();
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function test_ConstructorRevertsWithZeroAddresses() public {
        vm.expectRevert("!valid");
        new Locker(address(this), address(0), address(escrow));

        vm.expectRevert("!valid");
        new Locker(address(this), address(token), address(0));
    }

    // ============================================
    // setOperator Tests
    // ============================================

    function test_SetOperator() public {
        locker.setOperator(address(operator));
        assertEq(locker.operator(), address(operator));
    }

    function test_SetOperatorRevertsWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        vm.prank(user);
        locker.setOperator(address(operator));
    }

    function test_SetOperatorRevertsWithZeroAddress() public {
        vm.expectRevert("!valid");
        locker.setOperator(address(0));
    }

    // ============================================
    // execute Tests
    // ============================================

    function test_ExecuteByOwnerAndOperator() public {
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        // Owner can execute (owner is this test contract)
        (bool success, ) = locker.execute(payable(address(target)), 0, data);
        assertTrue(success);
        assertEq(target.value(), 42);

        // Operator can execute
        locker.setOperator(address(operator));
        vm.prank(address(operator));
        (success, ) = locker.execute(payable(address(target)), 0, data);
        assertTrue(success);
    }

    function test_ExecuteRevertsWhenNotAuthorized() public {
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        vm.expectRevert("!authorized");
        vm.prank(user);
        locker.execute(payable(address(target)), 0, data);
    }

    function test_ExecuteReturnsFailureForRevertingCall() public {
        target.setShouldRevert(true);
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42); // fake call
        (bool success, ) = locker.execute(payable(address(target)), 0, data);
        assertFalse(success);
    }

    // ============================================
    // safeExecute Tests
    // ============================================

    function test_SafeExecuteRevertsWhenNotAuthorized() public {
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);
        vm.expectRevert("!authorized");
        vm.prank(user);
        locker.safeExecute(payable(address(target)), 0, data);
    }

    function test_SafeExecuteRevertsOnFailedCall() public {
        target.setShouldRevert(true);
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);

        vm.expectRevert("call failed");
        locker.safeExecute(payable(address(target)), 0, data);
    }

    // ============================================
    // Edge Cases
    // ============================================

    function test_OperatorChangeRevokesAccess() public {
        locker.setOperator(address(operator));

        // Change to different operator
        address newOperator = address(0x4);
        locker.setOperator(newOperator);

        // Old operator can no longer execute
        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 100);
        vm.expectRevert("!authorized");
        vm.prank(address(operator));
        locker.execute(payable(address(target)), 0, data);
    }
}
