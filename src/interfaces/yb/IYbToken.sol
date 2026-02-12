// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYbToken is IERC20 {
    function STABLECOIN() external view returns (address);
    function ASSET_TOKEN() external view returns (address);
    function CRYPTOPOOL() external view returns (address);
    function preview_withdraw(uint256 shares) external view returns (uint256);
    function withdraw(uint256 shares, uint256 minAssets, address receiver) external returns (uint256);
}
