// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IOperator} from "src/interfaces/IOperator.sol";
import {ILocker} from "src/interfaces/ILocker.sol";

contract YToken is ERC20 {
    using SafeERC20 for IERC20;

    address payable public immutable locker;
    address public immutable token;

    event Swept(address indexed token, address indexed to, uint256 amount);

    modifier onlyOperator() {
        require(msg.sender == operator(), "Only locker");
        _;
    }

    constructor(
        address _locker,
        address _token,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        require(_locker != address(0), "!valid");
        require(_token != address(0), "!valid");
        locker = payable(_locker);
        token = _token;
    }

    function lock(uint256 amount, address to) external {
        require(amount > 0, "Amount must be > 0");
        IERC20(token).safeTransferFrom(msg.sender, locker, amount);
        IOperator(operator()).lock(amount);
        _mint(to, amount);
    }

    function mint(address to, uint256 amount) external onlyOperator {
        _mint(to, amount);
    }

    function sweep(address _token, address to, uint256 amount) external onlyOperator {
        IERC20(_token).safeTransfer(to, amount);
        emit Swept(_token, to, amount);
    }

    function operator() public view returns (address) {
        return ILocker(locker).operator();
    }
}
