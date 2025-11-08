// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract Locker is Ownable2Step {
    IERC20 public immutable TOKEN;
    address public immutable escrow;
    address public operator;

    event OperatorUpdated(address operator);
    event Executed(address indexed caller, address indexed to);

    modifier onlyOwnerOrOperator() {
        require(msg.sender == owner() || msg.sender == operator, "!authorized");
        _;
    }

    constructor(
        address _owner,
        address _token,
        address _escrow
    ) Ownable(_owner) {
        require(_token != address(0), "!valid");
        require(_escrow != address(0), "!valid");
        TOKEN = IERC20(_token);
        escrow = _escrow;
        IERC20(_token).approve(_escrow, type(uint256).max);
    }

    function setOperator(address _operator) external onlyOwner {
        require(_operator != address(0), "!valid");
        operator = _operator;
        emit OperatorUpdated(_operator);
    }

    /**
     *  @notice Use to execute arbitrary bytecode, and fail on reverts.
     *  @dev May only be called by governance or operator.
     *  @param _to Address this call is targeting.
     *  @param _value Ether value, if needed.
     *  @param _data Bytecode to be executed.
     */
    function safeExecute(
        address payable _to,
        uint256 _value,
        bytes calldata _data
    ) external payable returns (bool success, bytes memory result) {
        (success, result) = _execute(_to, _value, _data);
        require(success, "call failed");
    }

    /**
     *  @notice Use to execute arbitrary bytecode, even if it reverts.
     *  @dev May only be called by governance or operator.
     *  @param _to Address this call is targeting.
     *  @param _value Ether value, if needed.
     *  @param _data Bytecode to be executed.
     */
    function execute(
        address payable _to,
        uint256 _value,
        bytes calldata _data
    ) external payable returns (bool success, bytes memory result) {
        (success, result) = _execute(_to, _value, _data);
    }

    function _execute(
        address payable _to,
        uint256 _value,
        bytes calldata _data
    ) internal returns (bool success, bytes memory result) {
        require(msg.sender == operator || msg.sender == owner(), "!authorized");
        (success, result) = _to.call{value: _value}(_data);
        emit Executed(msg.sender, _to);
    }

    receive() external payable {}
}