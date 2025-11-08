// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILocker {
    // ----------- Events -----------
    event OperatorUpdated(address operator);
    event Executed(address indexed caller, address indexed to);

    // ----------- View Functions -----------
    function TOKEN() external view returns (address);
    function escrow() external view returns (address);
    function operator() external view returns (address);
    function owner() external view returns (address);

    // ----------- Write Functions -----------
    function setOperator(address _operator) external;

    function safeExecute(
        address payable _to,
        uint256 _value,
        bytes calldata _data
    ) external payable returns (bool success, bytes memory result);

    function execute(
        address payable _to,
        uint256 _value,
        bytes calldata _data
    ) external payable returns (bool success, bytes memory result);

    receive() external payable;
}