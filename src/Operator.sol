// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IYBTokenVoting, IYBTokenVotingOption, IMajorityVoting } from "./interfaces/yb/IYBTokenVoting.sol";
import { IYBGaugeController } from "./interfaces/yb/IYBGaugeController.sol";
import { IYBVotingEscrow } from "./interfaces/yb/IYBVotingEscrow.sol";
import { ILocker } from "./interfaces/ILocker.sol";

contract Operator {
    using SafeERC20 for IERC20;

    ILocker public immutable locker;
    IYBVotingEscrow public immutable escrow;
    address public immutable token;
    address public immutable gaugeController;
    address public immutable daoVoting;

    mapping(address => bool) public gaugeVoters;
    mapping(address => bool) public daoVoters;
    mapping(address => bool) public lockers;

    event GaugeVoterUpdated(address indexed voter, bool isVoter);
    event DaoVoterUpdated(address indexed voter, bool isVoter);
    event LockerUpdated(address indexed locker, bool isLocker);
    event Swept(address indexed token, address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner(), "!owner");
        _;
    }
    
    modifier onlyGaugeVoters() {
        require(gaugeVoters[msg.sender] || msg.sender == owner(), "!gauge voter");
        _;
    }
    
    modifier onlyDaoVoters() {
        require(daoVoters[msg.sender] || msg.sender == owner(), "!dao voter");
        _;
    }

    modifier onlyLockers() {
        require(lockers[msg.sender] || msg.sender == owner(), "!locker");
        _;
    }
    
    constructor(
        address payable _locker,
        address _gaugeController, 
        address _daoVoting
    ) {
        require(_locker != address(0), "!valid");
        token = ILocker(_locker).TOKEN();
        escrow = IYBVotingEscrow(ILocker(_locker).escrow());
        locker = ILocker(_locker);
        gaugeController = _gaugeController;
        daoVoting = _daoVoting;
    }

    function owner() public view returns (address) {
        return locker.owner();
    }

    
    // Gauge Voting
    function voteForGaugeWeights(address[] memory _gauges, uint256[] memory _weights) external onlyGaugeVoters {
        _execute(gaugeController, abi.encodeWithSelector(IYBGaugeController.vote_for_gauge_weights.selector, _gauges, _weights));
    }

    // DAO Vote
    function castDaoVote(uint256 _proposalId, uint8 _voteOption) external onlyDaoVoters {
        _execute(daoVoting, abi.encodeWithSelector(IYBTokenVotingOption.vote.selector, _proposalId, _voteOption, false));
    }

    // DAO Vote with split options
    function castSplitDaoVote(uint256 _proposalId, IMajorityVoting.Tally memory _votes) external onlyDaoVoters {
        _execute(daoVoting, abi.encodeWithSelector(IYBTokenVoting.vote.selector, _proposalId, _votes, false));
    }

    // Lock Management
    function lock(uint256 amount) external onlyLockers {
        _execute(address(escrow), abi.encodeWithSelector(IYBVotingEscrow.increase_amount.selector, amount));
    }

    function transferAndLock(uint256 amount) external onlyLockers {
        IERC20(token).safeTransferFrom(msg.sender, address(locker), amount);
        _execute(address(escrow), abi.encodeWithSelector(IYBVotingEscrow.increase_amount.selector, amount));
    }

    function increaseLock(uint256 amount) external onlyLockers {
        _execute(address(locker), abi.encodeWithSelector(IYBVotingEscrow.increase_amount.selector, amount));
    }
    
    function getLockTimeRemaining() external view returns (uint256) {
        (, uint256 end) = escrow.locked(address(locker));
        if (end < block.timestamp) return 0;
        if (end == type(uint256).max) return type(uint256).max;
        return end - block.timestamp;
    }

    function getLockedBalance() external view returns (uint256) {
        return escrow.getVotes(address(locker));
    }

    // Locker Execution
    function _execute(address _to, bytes memory _data) internal returns (bool success, bytes memory result) {
        return _executeWithValue(0, _to, _data);
    }

    function _executeWithValue(uint256 _value, address _to, bytes memory _data) internal returns (bool success, bytes memory result) {
        return locker.safeExecute{value: _value}(payable(_to), _value, _data);
    }

    // Setters
    function authorizeGaugeVoter(address _voter, bool _isVoter) external onlyOwner {
        gaugeVoters[_voter] = _isVoter;
        emit GaugeVoterUpdated(_voter, _isVoter);
    }
    
    function authorizeDaoVoter(address _voter, bool _isVoter) external onlyOwner {
        daoVoters[_voter] = _isVoter;
        emit DaoVoterUpdated(_voter, _isVoter);
    }

    function authorizeLocker(address _locker, bool _isLocker) external onlyOwner {
        lockers[_locker] = _isLocker;
        emit LockerUpdated(_locker, _isLocker);
    }

    function sweep(address _token, address to, uint256 amount) external onlyOwner {
        IERC20(_token).safeTransfer(to, amount);
        emit Swept(_token, to, amount);
    }

    receive() external payable {}
}