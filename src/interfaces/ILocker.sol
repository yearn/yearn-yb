// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILocker {
    // ----------- Events -----------
    event OperatorUpdated(address operator);
    event YLockerTokenSet(address indexed yLockerToken);
    event Executed(address indexed caller, address indexed to);
    event NFTReceived(address indexed from, uint256 indexed tokenId, address indexed recipient, uint256 amount);

    // ----------- View Functions -----------
    function TOKEN() external view returns (address);
    function escrow() external view returns (address);
    function operator() external view returns (address);
    function owner() external view returns (address);
    function yLockerToken() external view returns (address);
    function lastLockedAmount() external view returns (uint256);
    function getLockedAmount() external view returns (uint256);

    // ----------- Write Functions -----------
    function setOperator(address _operator) external;
    function setYLockerToken(address _yLockerToken) external;
    function updateLockedAmount() external;

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

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}