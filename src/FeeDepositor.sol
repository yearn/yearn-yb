// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IYToken } from "src/interfaces/IYToken.sol";

interface IFeeDistributor {
    function claim(address receiver, uint256 epoch_count, bool use_vest) external;
    function preview_distribution(int256 week_shift) external view returns (address[] memory, uint256[] memory);
    function depositReward(uint256 amount) external;
    function rewardToken() external view returns(address);
}

contract FeeDepositor {
    using SafeERC20 for IERC20;

    address public constant YTOKEN = 0x22222222aEA0076fCA927a3f44dc0B4FdF9479D6;
    address public constant YVCRVUSD = 0xBF319dDC2Edc1Eb6FDf9910E39b37Be221C8805F;
    address public constant REWARD_DISTRIBUTOR = 0x1d02F6A86Ed5650f93E40FCD62fa5727c32ad746;

    IFeeDistributor public immutable ybDistributor;
    address public immutable CRVUSD;

    mapping(address => bool) public approvedCallers;

    // --- New: external spender (upgradeable) ---
    address public depositor;

    // Track tokens we've ever approved so we can revoke on depositor upgrade
    address[] public trackedTokens;
    mapping(address => bool) public isTracked;

    event SetApprovedCaller(address indexed account, bool approved);
    event DepositorSet(address indexed oldDepositor, address indexed newDepositor);
    event TokenTracked(address indexed token);
    event DepositorApprovalSet(address indexed token, address indexed spender, uint256 amount);

    modifier onlyApprovedCallers() {
        require(approvedCallers[msg.sender], "!approved");
        _;
    }

    modifier onlyLockerOwner() {
        require(
            msg.sender == IYToken(YTOKEN).owner() ||
            msg.sender == locker(),
            "!owner");
        _;
    }

    constructor(address _ybDistributor) {
        require(_ybDistributor != address(0), "!valid");
        ybDistributor = IFeeDistributor(_ybDistributor);

        CRVUSD = IERC4626(YVCRVUSD).asset();

        // existing internal approvals
        IERC20(YVCRVUSD).forceApprove(REWARD_DISTRIBUTOR, type(uint256).max);
        IERC20(CRVUSD).forceApprove(YVCRVUSD, type(uint256).max);
    }

    /// -----------------------------------------------------------------------
    /// Depositor approval management
    /// -----------------------------------------------------------------------

    /// @notice Set/upgrade the external Depositor (spender).
    /// Clears allowances for the old depositor across all tracked tokens,
    /// and grants max allowances for the new depositor for current-week tokens.
    function setDepositor(address _depositor) external onlyLockerOwner {
        address old = depositor;
        depositor = _depositor;
        emit DepositorSet(old, _depositor);

        // revoke old depositor allowances for all tokens we've ever approved
        if (old != address(0)) {
            uint256 n = trackedTokens.length;
            for (uint256 i = 0; i < n; ++i) {
                IERC20(trackedTokens[i]).forceApprove(old, 0);
                emit DepositorApprovalSet(trackedTokens[i], old, 0);
            }
        }

        // grant new depositor allowances for current active tokens (this week)
        if (_depositor != address(0)) {
            _syncApprovals(_depositor);
        }
    }

    /// @notice Ensure the current depositor has max allowance for this week's active tokens.
    /// @dev Call this at the start of the depositor's weekly pull flow (before transferFrom).
    function syncApprovals() external {
        address _depositor = depositor;
        require(_depositor != address(0), "depositor not set");
        _syncApprovals(_depositor);
    }

    function _syncApprovals(address _depositor) internal {
        (address[] memory tokens, ) = ybDistributor.preview_distribution(0);

        address crvUsd = IERC4626(YVCRVUSD).asset();
        uint256 length = tokens.length;

        for (uint256 i = 0; i < length; ++i) {
            address token = tokens[i];

            // skip tokens we don't want depositor pulling via allowance
            if (token == crvUsd || token == YVCRVUSD) continue;
            if (token == address(0)) continue;

            // track for future revocation on depositor upgrade
            if (!isTracked[token]) {
                isTracked[token] = true;
                trackedTokens.push(token);
                emit TokenTracked(token);
            }

            // ensure max allowance
            uint256 a = IERC20(token).allowance(address(this), _depositor);
            if (a < type(uint256).max / 2) {
                IERC20(token).forceApprove(_depositor, type(uint256).max);
                emit DepositorApprovalSet(token, _depositor, type(uint256).max);
            }
        }
    }

    function trackedTokensLength() external view returns (uint256) {
        return trackedTokens.length;
    }

    function claimAndPull(uint256 epochCount) external onlyApprovedCallers {
        ybDistributor.claim(address(this), epochCount, false);
        pullTokens();
    }

    function pullTokens() public onlyApprovedCallers {
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
                IERC20(token).safeTransfer(locker(), balance);
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
        IFeeDistributor(REWARD_DISTRIBUTOR).depositReward(rewardAmount);
    }

    function setApprovedCaller(address _account, bool _approved) external onlyLockerOwner {
        approvedCallers[_account] = _approved;
        emit SetApprovedCaller(_account, _approved);
    }

    function locker() public view returns(address) {
        return IYToken(YTOKEN).locker();
    }
}