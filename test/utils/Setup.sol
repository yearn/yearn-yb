// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Locker } from "src/Locker.sol";
import { Operator } from "src/Operator.sol";
import { IYBVotingEscrow } from "src/interfaces/yb/IYBVotingEscrow.sol";
import { IYBGaugeController } from "src/interfaces/yb/IYBGaugeController.sol";
import { IYBTokenVoting, Action, IMajorityVoting, MajorityVotingBase } from "src/interfaces/yb/IYBTokenVoting.sol";
import { YB } from "src/utils/Constants.sol";

contract Setup is Test {
    uint256 public constant MAX_LOCK_TIME = 4 * 365 days;
    uint256 public mainnetFork;

    Locker public locker;
    Operator public operator;
    IERC20 public token;
    IYBVotingEscrow public escrow;
    IYBGaugeController public gaugeController;
    IYBTokenVoting public daoVoting;

    function setUp() public virtual {
        string memory mainnetRpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://eth.llamarpc.com"));
        mainnetFork = vm.createSelectFork(mainnetRpcUrl);

        token = IERC20(YB.TOKEN);
        escrow = IYBVotingEscrow(YB.VEYB);
        gaugeController = IYBGaugeController(YB.GAUGE_CONTROLLER);
        daoVoting = IYBTokenVoting(YB.DAO_VOTING);

        locker = new Locker(address(this), address(token), address(escrow));
        operator = new Operator(payable(address(locker)), address(gaugeController), address(daoVoting));
        locker.setOperator(address(operator));

        // Initialize our lock
        createLock(address(locker), 1_000_000e18, block.timestamp + 365 days);
    }

    function createLock(address user, uint256 _amount, uint256 _unlockTime) public {
        // require(escrow.locked(user) == 0, "Lock already exists");
        deal(address(token), user, _amount);
        vm.startPrank(user);
        if (token.allowance(user, address(escrow)) < type(uint256).max) {
            token.approve(address(escrow), type(uint256).max);
        }
        escrow.create_lock(_amount, _unlockTime);
        vm.stopPrank();
        skip(1);
    }

    function increaseLock(address user, uint256 _amount) public {
        deal(address(token), user, _amount);
        vm.startPrank(user);
        if (token.allowance(user, address(escrow)) < _amount) {
            token.approve(address(escrow), _amount);
        }
        escrow.increase_amount(_amount);
        vm.stopPrank();
    }

    function createDaoProposal() public returns (uint256 proposalId) {
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            to: address(operator),
            value: 0,
            data: ""
        });
        vm.prank(address(locker));
        proposalId = daoVoting.createProposal(
            bytes("Test Proposal"),
            actions,
            uint64(block.timestamp), // startTime
            uint64(block.timestamp + 7 days), // endTime
            bytes("")
        );
        skip(1);
    }

    function getPastVotingPower(uint256 _ts) public view returns (uint256) {
        return escrow.getPastVotes(address(locker), _ts);
    }

    function getLatestProposalId() public view returns (uint256) {
        return daoVoting.proposalCount() - 1;
    }

    function getProposalInfo(uint256 _proposalId) public view returns (bool, bool, MajorityVotingBase.ProposalParameters memory, IMajorityVoting.Tally memory, Action[] memory, uint256) {
        (
            bool open, 
            bool executed, 
            MajorityVotingBase.ProposalParameters memory parameters, 
            IMajorityVoting.Tally memory tally, 
            Action[] memory actions, 
            uint256 allowFailureMap, 
        ) = daoVoting.getProposal(_proposalId);
        return (open, executed, parameters, tally, actions, allowFailureMap);
    }
}
