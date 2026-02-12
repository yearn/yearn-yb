// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { FeeSwapper } from "src/utils/FeeSwapper.sol";
import { IYbToken } from "src/interfaces/yb/IYbToken.sol";

contract FeeSwapperTest is Test {
    address public constant YB_TOKEN = 0xAC0cfa7742069a8af0c63e14FFD0fe6b3e1Bf8D2; // yb-cbBTC (example)

    FeeSwapper public swapper;
    IERC20 public yb_token;
    IERC20 public stablecoin;

    function setUp() public {
        string memory mainnetRpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://eth.llamarpc.com"));
        vm.createSelectFork(mainnetRpcUrl);

        swapper = new FeeSwapper();
        yb_token = IERC20(YB_TOKEN);
        stablecoin = IERC20(IYbToken(YB_TOKEN).STABLECOIN());
    }

    function test_PreviewSwap() public {
        uint256 shares = 1e18;
        deal(address(yb_token), address(this), shares);

        uint256 quote = swapper.previewSwap(address(yb_token), shares);
        assertGt(quote, 0);
    }

    function test_Swap() public {
        uint256 shares = 1e18;
        deal(address(yb_token), address(this), shares);
        yb_token.approve(address(swapper), type(uint256).max);

        uint256 quote = swapper.previewSwap(address(yb_token), shares);
        uint256 minStableOut = quote * 99 / 100;

        uint256 stableBefore = stablecoin.balanceOf(address(this));
        uint256 ybBefore = yb_token.balanceOf(address(this));

        uint256 out = swapper.swap(address(yb_token), shares, minStableOut);

        assertGt(out, 0);
        assertEq(yb_token.balanceOf(address(this)), ybBefore - shares);
        assertEq(stablecoin.balanceOf(address(this)), stableBefore + out);
    }

    function test_SwapRevertsWithHighMinOut() public {
        uint256 shares = 1e18;
        deal(address(yb_token), address(this), shares);
        yb_token.approve(address(swapper), type(uint256).max);

        uint256 quote = swapper.previewSwap(address(yb_token), shares);

        vm.expectRevert();
        swapper.swap(address(yb_token), shares, quote + 1);
    }
}
