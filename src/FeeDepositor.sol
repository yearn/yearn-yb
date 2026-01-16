// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ILocker } from "src/interfaces/ILocker.sol";

interface IFeeDistributor {
    function claim(address receiver, uint256 epoch_count, bool use_vest) external;
    function preview_distribution(int256 week_shift) external view returns (address[] memory, uint256[] memory);
    function depositReward(uint256 amount) external;
    function rewardToken() external view returns(address);
}

contract FeeDepositor {
    using SafeERC20 for IERC20;

    address public constant LOCKER = 0x0000000C90799449af8eE0B240Da639144a36C6A;
    address public constant YVCRVUSD = 0xBF319dDC2Edc1Eb6FDf9910E39b37Be221C8805F;
    address public constant REWARD_DISTRIBUTOR = 0x1d02F6A86Ed5650f93E40FCD62fa5727c32ad746;
    IFeeDistributor public immutable ybDistributor;
    address public immutable CRVUSD;
    mapping(address => bool) public approved;

    event SetApproved(address indexed account, bool approved);

    modifier onlyApproved() {
        require(approved[msg.sender], "!approved");
        _;
    }

    constructor(address _ybDistributor) {
        require(_ybDistributor != address(0), "!valid");
        ybDistributor = IFeeDistributor(_ybDistributor);
        CRVUSD = IERC4626(YVCRVUSD).asset();
        IERC20(YVCRVUSD).forceApprove(REWARD_DISTRIBUTOR, type(uint256).max);
        IERC20(CRVUSD).forceApprove(YVCRVUSD, type(uint256).max);
    }

    function claimAndSweep(uint256 epochCount) external onlyApproved {
        ybDistributor.claim(address(this), epochCount, false);
        sweepActiveTokens();
    }

    function sweepActiveTokens() public onlyApproved {
        (address[] memory tokens, ) = ybDistributor.preview_distribution(0);
        address crvUsd = IERC4626(YVCRVUSD).asset();
        uint256 length = tokens.length;

        for (uint256 i = 0; i < length; ++i) {
            address token = tokens[i];
            if (token == crvUsd || token == YVCRVUSD) {
                continue;
            }
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(LOCKER, balance);
            }
        }
    }

    function depositCrvUsdToRewards() external {
        uint256 amount = IERC20(CRVUSD).balanceOf(address(this));
        uint256 rewardAmount = IERC20(YVCRVUSD).balanceOf(address(this));
        if (amount != 0) {
            rewardAmount += IERC4626(YVCRVUSD).deposit(amount, address(this));
        }
        if (rewardAmount == 0) return;
        if (rewardAmount > 0) {
            IFeeDistributor(REWARD_DISTRIBUTOR).depositReward(rewardAmount);
        }
    }

    function setApproved(address _account, bool _approved) external {
        require(msg.sender == ILocker(LOCKER).owner(), "!owner");
        approved[_account] = _approved;
        emit SetApproved(_account, _approved);
    }
}
