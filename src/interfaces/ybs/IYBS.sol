// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYBS {
    function stakeFor(address account, uint256 amount) external returns (uint256);

    function unstakeFor(
        address account,
        uint256 amount,
        address receiver
    ) external returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}
