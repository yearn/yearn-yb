// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ICurveCryptoPool2 } from "src/interfaces/curve/ICurveCryptoPool2.sol";
import { IYbToken } from "src/interfaces/yb/IYbToken.sol";

/// @notice Pull approved yb-token shares, withdraw to the underlying asset, and swap to the token's stablecoin (e.g. crvUSD).
/// @dev Assumes Yield Basis LT pools keep coins as [stablecoin, asset], so swap direction is always 1 -> 0.
contract FeeSwapper {
    using SafeERC20 for IERC20;

    event Swapped(
        address indexed yb_token,
        address indexed caller,
        address indexed receiver,
        uint256 sharesIn,
        uint256 assetOut,
        uint256 stableOut
    );

    /// @notice Preview stablecoin output for swapping yb-token shares.
    /// @dev Intended for off-chain quoting to derive `minStableOut` for `swap`.
    function previewSwap(
        address yb_token,
        uint256 shares
    ) external view returns (uint256 stableOut) {
        require(yb_token != address(0), "!ybToken");

        IYbToken yb = IYbToken(yb_token);
        if (shares == type(uint256).max) {
            shares = yb.balanceOf(msg.sender);
        }
        require(shares > 0, "!shares");

        address asset = yb.ASSET_TOKEN();
        address stable = yb.STABLECOIN();
        ICurveCryptoPool2 pool = ICurveCryptoPool2(yb.CRYPTOPOOL());

        require(pool.coins(0) == stable, "!coin0");
        require(pool.coins(1) == asset, "!coin1");

        uint256 assetOut = yb.preview_withdraw(shares);
        return pool.get_dy(1, 0, assetOut);
    }

    /// @notice Swap yb-token shares to stablecoin and send to caller.
    function swap(
        address yb_token,
        uint256 shares,
        uint256 minStableOut
    ) external returns (uint256 stableOut) {
        return _swap(yb_token, shares, minStableOut, msg.sender);
    }

    /// @notice Swap yb-token shares to stablecoin.
    /// @param yb_token Yield Basis LT token.
    /// @param shares Amount of yb-token shares to swap (`type(uint256).max` = full caller balance).
    /// @param minStableOut Minimum stablecoin amount expected from pool `exchange`.
    /// @param receiver Receiver of output stablecoin (`address(0)` defaults to caller).
    function swap(
        address yb_token,
        uint256 shares,
        uint256 minStableOut,
        address receiver
    ) external returns (uint256 stableOut) {
        return _swap(yb_token, shares, minStableOut, receiver);
    }

    function _swap(
        address yb_token,
        uint256 shares,
        uint256 minStableOut,
        address receiver
    ) internal returns (uint256 stableOut) {
        require(yb_token != address(0), "!ybToken");

        IYbToken yb = IYbToken(yb_token);

        if (shares == type(uint256).max) {
            shares = yb.balanceOf(msg.sender);
        }
        require(shares > 0, "!shares");
        if (receiver == address(0)) {
            receiver = msg.sender;
        }

        address asset = yb.ASSET_TOKEN();
        address stable = yb.STABLECOIN();
        ICurveCryptoPool2 pool = ICurveCryptoPool2(yb.CRYPTOPOOL());

        require(pool.coins(0) == stable, "!coin0");
        require(pool.coins(1) == asset, "!coin1");

        IERC20(yb_token).safeTransferFrom(msg.sender, address(this), shares);

        uint256 assetOut = yb.withdraw(shares, 0, address(this));
        IERC20(asset).forceApprove(address(pool), assetOut);

        stableOut = pool.exchange(1, 0, assetOut, minStableOut, receiver);

        emit Swapped(yb_token, msg.sender, receiver, shares, assetOut, stableOut);
    }
}
