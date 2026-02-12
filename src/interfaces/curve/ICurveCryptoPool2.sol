// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

interface ICurveCryptoPool2 {
    function coins(uint256 i) external view returns (address);
    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 minDy, address receiver) external returns (uint256);
}
