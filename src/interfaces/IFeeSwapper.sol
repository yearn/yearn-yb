// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

interface IFeeSwapper {
    function previewSwap(address yb_token, uint256 shares) external view returns (uint256 stableOut);
    function swap(address yb_token, uint256 shares, uint256 minStableOut, address receiver) external returns (uint256 stableOut);
}
