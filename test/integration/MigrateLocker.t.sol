// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Locker } from "src/Locker.sol";
import { Operator } from "src/Operator.sol";
import { YToken } from "src/YToken.sol";
import { IYBVotingEscrow } from "src/interfaces/yb/IYBVotingEscrow.sol";
import { IYBGaugeController } from "src/interfaces/yb/IYBGaugeController.sol";
import { IYBTokenVoting } from "src/interfaces/yb/IYBTokenVoting.sol";
import { ILocker } from "src/interfaces/ILocker.sol";
import { Protocol, YB } from "src/utils/Constants.sol";

contract MigrateLockerTest is Test {
    // Pre-migration state where the old Locker owns its NFT and transfers are enabled.
    uint256 internal constant MIGRATION_BLOCK = 24_249_541;

    uint256 public mainnetFork;

    IERC20 public token;
    IYBVotingEscrow public escrow;
    IYBGaugeController public gaugeController;
    IYBTokenVoting public daoVoting;

    ILocker public oldLocker;
    YToken public yToken;
    Locker public newLocker;

    function setUp() public {
        string memory mainnetRpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://eth.llamarpc.com"));
        mainnetFork = vm.createSelectFork(mainnetRpcUrl, MIGRATION_BLOCK);

        token = IERC20(YB.TOKEN);
        escrow = IYBVotingEscrow(YB.VEYB);
        gaugeController = IYBGaugeController(YB.GAUGE_CONTROLLER);
        daoVoting = IYBTokenVoting(YB.DAO_VOTING);

        oldLocker = ILocker(Protocol.OLD_LOCKER);
        yToken = YToken(Protocol.YTOKEN);

        _deployNewLocker();
    }

    function test_MigrateToNewLocker() public {
        address owner = oldLocker.owner();

        // Capture state before migration
        uint256 oldLockerVotes = escrow.getVotes(Protocol.OLD_LOCKER);
        assertGt(oldLockerVotes, 0, "Old locker should have votes");

        // Transfer NFT from old locker to new locker
        uint256 tokenId = escrow.tokenOfOwnerByIndex(Protocol.OLD_LOCKER, 0);
        vm.prank(Protocol.OLD_LOCKER);
        escrow.safeTransferFrom(Protocol.OLD_LOCKER, Protocol.LOCKER, tokenId);

        // Verify NFT transfer
        assertEq(escrow.getVotes(Protocol.OLD_LOCKER), 0, "Old locker should have 0 votes");
        assertGt(escrow.getVotes(Protocol.LOCKER), 0, "New locker should have votes");

        // Update YToken.locker to point to new locker
        vm.prank(owner);
        yToken.setLocker(Protocol.LOCKER);
        assertEq(yToken.locker(), Protocol.LOCKER, "YToken locker should be updated");

        // Deploy new Operator pointing to new locker
        Operator newOperator = new Operator(
            payable(Protocol.LOCKER),
            address(gaugeController),
            address(daoVoting),
            address(yToken)
        );

        // Cache not yet updated
        assertLt(newOperator.cachedLockedAmount(), newOperator.getLockedAmount());

        // Set operator on new locker
        vm.prank(owner);
        newLocker.setOperator(address(newOperator));

        // Cache now updated
        assertEq(newOperator.cachedLockedAmount(), newOperator.getLockedAmount());

        // Verify new operator state
        assertGt(newOperator.getLockedAmount(), 0, "New operator should have locked amount");
        assertGt(newOperator.getVotes(), 0, "New operator should have votes");
        assertGt(newOperator.cachedLockedAmount(), 0, "Cached locked amount should be set");
        assertEq(newOperator.cachedLockedAmount(), newOperator.getLockedAmount(), "Cache should match actual");

        // Verify yToken authorization chain
        assertTrue(newOperator.lockers(address(yToken)), "yToken should be authorized locker");
        assertEq(yToken.operator(), address(newOperator), "yToken.operator() should return new operator");
        assertEq(yToken.owner(), owner, "yToken.owner() should return owner via new locker");

        // Verify new locker state
        assertEq(newLocker.owner(), owner, "Owner should be preserved");
        assertEq(newLocker.operator(), address(newOperator), "Operator should be set");
        assertEq(address(newLocker.TOKEN()), address(token), "TOKEN immutable should be correct");
        assertEq(newLocker.escrow(), address(escrow), "escrow immutable should be correct");

        skip(1);

        // Test that lock function works through new operator
        uint256 lockedBefore = newOperator.getLockedAmount();
        uint256 amt = 1000e18;
        deal(address(token), address(this), amt);
        token.approve(address(yToken), type(uint256).max);
        yToken.mint(amt, address(this));
        assertGt(newOperator.getLockedAmount(), lockedBefore, "Lock should increase locked amount");
        assertEq(newOperator.cachedLockedAmount(), newOperator.getLockedAmount(), "Cache should be updated");
    }

    function _deployNewLocker() internal {
        address owner = oldLocker.owner();

        // Deploy temp Locker to get bytecode with correct immutables
        address tempAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        deal(address(token), tempAddress, 1e18);
        Locker tempLocker = new Locker(owner, address(token), address(escrow));

        // Copy bytecode to Protocol.LOCKER (vm.etch copies code including immutables)
        vm.etch(Protocol.LOCKER, address(tempLocker).code);
        newLocker = Locker(payable(Protocol.LOCKER));

        // Set storage slots for Ownable2Step
        // Slot 0: _owner (from Ownable)
        vm.store(Protocol.LOCKER, bytes32(0), bytes32(uint256(uint160(owner))));

        // Setup TOKEN approval to escrow (required for increase_amount and create_lock)
        vm.prank(Protocol.LOCKER);
        token.approve(address(escrow), type(uint256).max);

        // Create a small lock for Protocol.LOCKER (required before infinite_lock_toggle)
        deal(address(token), Protocol.LOCKER, 1e18);
        vm.prank(Protocol.LOCKER);
        escrow.create_lock(1e18, block.timestamp + 365 days);

        // Toggle infinite lock on new locker (required to receive veYB NFT)
        vm.prank(Protocol.LOCKER);
        escrow.infinite_lock_toggle();
    }
}
