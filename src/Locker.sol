// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IOperator } from "src/interfaces/IOperator.sol";
import { IYBVotingEscrow } from "src/interfaces/yb/IYBVotingEscrow.sol";

contract Locker is Ownable2Step, IERC721Receiver {
    using SafeERC20 for IERC20;

    IERC20 public immutable TOKEN;
    address public immutable escrow;
    bytes4 public immutable INCREASE_AMOUNT_SELECTOR;
    address public operator;

    event OperatorUpdated(address operator);
    event Executed(address indexed caller, address indexed to);

    constructor(
        address _owner,
        address _token,
        address _escrow
    ) Ownable(_owner) {
        require(_token != address(0), "!valid");
        require(_escrow != address(0), "!valid");
        TOKEN = IERC20(_token);
        escrow = _escrow;
        IERC20(_token).forceApprove(_escrow, type(uint256).max);
        INCREASE_AMOUNT_SELECTOR = IYBVotingEscrow.increase_amount.selector;
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

        // If calling escrow with blocked selector, must be operator
        if (_to == escrow && _data.length >= 4) {
            bytes4 selector = bytes4(_data[:4]);
            if (selector == INCREASE_AMOUNT_SELECTOR) require(msg.sender == operator, "Blocked selector");
        }

        (success, result) = _to.call{value: _value}(_data);
        emit Executed(msg.sender, _to);
    }

    /**
     * @notice Callback for receiving ERC721 NFTs (veYB position transfers)
     * @dev Automatically mints yYB tokens to the specified recipient
     * @param from The owner of the NFT transferring being transferred
     * @param tokenId The NFT token ID
     * @param data Encoded (recipient) for yYB minting. Default to sender if not provided.
     */
    function onERC721Received(
        address, // caller
        address from, // owner of the NFT
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        require(msg.sender == escrow, "Only escrow NFTs");
        address recipient = from;
        if (data.length != 0) {
            recipient = abi.decode(data, (address));
            recipient = recipient == address(0) ? from : recipient;
        }
        address _operator = operator;
        if (_operator != address(0)) IOperator(_operator).nftTransferCallback(from, tokenId, recipient);

        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}