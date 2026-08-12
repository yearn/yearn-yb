// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FeeDepositor} from "src/FeeDepositor.sol";
import {Operator} from "src/Operator.sol";
import {IFeeSwapper} from "src/interfaces/IFeeSwapper.sol";
import {ILocker} from "src/interfaces/ILocker.sol";
import {IYToken} from "src/interfaces/IYToken.sol";
import {YB} from "src/utils/Constants.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract MockFeeDistributor {
    IERC20 public immutable token;
    uint256 public immutable claimAmount;

    constructor(IERC20 _token, uint256 _claimAmount) {
        token = _token;
        claimAmount = _claimAmount;
    }

    function preview_claim(address receiver, uint256, bool)
        external
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        _transferClaim(receiver);
        tokens = new address[](1);
        amounts = new uint256[](1);
        tokens[0] = address(token);
        amounts[0] = claimAmount;
    }

    function claim(address receiver, uint256, bool) external {
        _transferClaim(receiver);
    }

    function preview_distribution(int256) external view returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = new address[](1);
        amounts = new uint256[](1);
        tokens[0] = address(token);
    }

    function claimed_epoch_for(address, address claimedToken) external view returns (uint256) {
        return claimedToken == address(token) ? 1 : 0;
    }

    function _transferClaim(address receiver) internal {
        if (claimAmount == 0) return;
        require(token.transfer(receiver, claimAmount), "claim transfer failed");
    }
}

contract MockFeeSwapper is IFeeSwapper {
    using SafeERC20 for IERC20;

    IERC20 public immutable stable;

    constructor(IERC20 _stable) {
        stable = _stable;
    }

    function previewSwap(address, uint256 shares) external pure returns (uint256 stableOut) {
        return shares;
    }

    function swap(address ybToken, uint256 shares, uint256 minStableOut, address receiver)
        external
        returns (uint256 stableOut)
    {
        require(shares >= minStableOut, "slippage");
        IERC20(ybToken).safeTransferFrom(msg.sender, address(this), shares);
        stable.safeTransfer(receiver, shares);
        return shares;
    }
}

contract FalseReturnERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address account, uint256 amount) external {
        balanceOf[account] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract FeeDepositorTest is Test {
    uint256 internal constant CLAIM_AMOUNT = 7e18;
    uint256 internal constant LOCKER_BALANCE = 11e18;
    uint256 internal constant DEPOSITOR_BALANCE = 13e18;

    MockERC20 internal feeToken;
    FeeDepositor internal feeDepositor;
    MockFeeSwapper internal swapper;
    Operator internal operator;
    address internal locker;
    address internal owner;

    function setUp() public {
        string memory mainnetRpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://eth.llamarpc.com"));
        vm.createSelectFork(mainnetRpcUrl);

        feeToken = new MockERC20("Fee Token", "FEE");
        MockFeeDistributor mockDistributor = new MockFeeDistributor(IERC20(address(feeToken)), CLAIM_AMOUNT);
        vm.etch(YB.FEE_DISTRIBUTOR, address(mockDistributor).code);

        feeToken.mint(YB.FEE_DISTRIBUTOR, CLAIM_AMOUNT);
        feeDepositor = new FeeDepositor();
        swapper = new MockFeeSwapper(IERC20(feeDepositor.CRVUSD()));
        locker = feeDepositor.locker();
        owner = IYToken(feeDepositor.YTOKEN()).owner();
        operator = new Operator(payable(locker), YB.GAUGE_CONTROLLER, YB.DAO_VOTING, feeDepositor.YTOKEN());

        vm.startPrank(owner);
        operator.setFeeDepositor(address(feeDepositor));
        ILocker(locker).setOperator(address(operator));
        feeDepositor.setSwapper(address(swapper));
        feeDepositor.setApprovedCaller(address(this), true);
        vm.stopPrank();
    }

    function test_PreviewSwapsCountsPendingClaimOnce() public {
        feeToken.mint(feeDepositor.locker(), LOCKER_BALANCE);
        feeToken.mint(address(feeDepositor), DEPOSITOR_BALANCE);

        address[] memory tokens = new address[](1);
        tokens[0] = address(feeToken);

        uint256 snapshot = vm.snapshotState();
        (, uint256[] memory quotedOuts) = feeDepositor.previewSwaps(tokens);
        vm.revertToState(snapshot);

        assertEq(quotedOuts.length, 1);
        assertEq(quotedOuts[0], CLAIM_AMOUNT + LOCKER_BALANCE + DEPOSITOR_BALANCE);
    }

    function test_ConvertAndDepositFeesEndToEnd() public {
        feeToken.mint(locker, LOCKER_BALANCE);
        feeToken.mint(address(feeDepositor), DEPOSITOR_BALANCE);

        address[] memory tokens = new address[](1);
        tokens[0] = address(feeToken);

        uint256 snapshot = vm.snapshotState();
        (, uint256[] memory quotedOuts) = feeDepositor.previewSwaps(tokens);
        vm.revertToState(snapshot);

        uint256 expectedAmount = CLAIM_AMOUNT + LOCKER_BALANCE + DEPOSITOR_BALANCE;
        assertEq(quotedOuts[0], expectedAmount);

        uint256 rewardsBefore = IERC20(feeDepositor.YVCRVUSD()).balanceOf(feeDepositor.REWARD_DISTRIBUTOR());
        deal(feeDepositor.CRVUSD(), address(swapper), quotedOuts[0]);
        feeDepositor.convertAndDepositFees(tokens, quotedOuts);

        assertEq(feeToken.balanceOf(locker), 0);
        assertEq(feeToken.balanceOf(address(feeDepositor)), 0);
        assertEq(feeToken.balanceOf(address(swapper)), expectedAmount);
        assertEq(feeToken.allowance(address(feeDepositor), address(swapper)), type(uint256).max);
        assertEq(IERC20(feeDepositor.CRVUSD()).balanceOf(address(feeDepositor)), 0);
        assertEq(IERC20(feeDepositor.YVCRVUSD()).balanceOf(address(feeDepositor)), 0);
        assertGt(IERC20(feeDepositor.YVCRVUSD()).balanceOf(feeDepositor.REWARD_DISTRIBUTOR()), rewardsBefore);
    }

    function test_ProcessFeesRejectsFalseTransferReturn() public {
        FalseReturnERC20 falseToken = new FalseReturnERC20();
        MockFeeDistributor mockDistributor = new MockFeeDistributor(IERC20(address(falseToken)), 0);
        vm.etch(YB.FEE_DISTRIBUTOR, address(mockDistributor).code);
        falseToken.mint(locker, 1e18);

        address[] memory tokens = new address[](1);
        tokens[0] = address(falseToken);

        vm.expectRevert("!transfer");
        vm.prank(address(feeDepositor));
        operator.processFees(tokens);
    }
}
