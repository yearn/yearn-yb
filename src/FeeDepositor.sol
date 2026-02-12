// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IYToken } from "src/interfaces/IYToken.sol";
import { IFeeSwapper } from "src/interfaces/IFeeSwapper.sol";

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

    // External swapper (upgradeable)
    address public swapper;

    // Track tokens we've ever approved so we can revoke on swapper upgrade
    address[] public trackedTokens;
    mapping(address => bool) public isTracked;

    event SetApprovedCaller(address indexed account, bool approved);
    event SwapperSet(address indexed oldSwapper, address indexed newSwapper);
    event TokenTracked(address indexed token);
    event SwapperApprovalSet(address indexed token, address indexed spender, uint256 amount);
    event TokenSwapped(address indexed token, uint256 amountIn, uint256 stableOut);

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
    /// Swapper approval management
    /// -----------------------------------------------------------------------

    /// @notice Set/upgrade external swapper and rotate approvals.
    /// Revokes all tracked token approvals from old swapper, then grants max approvals to new swapper.
    function setSwapper(address _swapper) public onlyLockerOwner {
        address old = swapper;
        swapper = _swapper;
        emit SwapperSet(old, _swapper);

        uint256 n = trackedTokens.length;

        // revoke old swapper allowances across all tracked tokens
        if (old != address(0)) {
            for (uint256 i = 0; i < n; ++i) {
                IERC20(trackedTokens[i]).forceApprove(old, 0);
                emit SwapperApprovalSet(trackedTokens[i], old, 0);
            }
        }

        // grant new swapper allowances across tracked and current active tokens
        if (_swapper != address(0)) {
            _syncSwapperApprovals(_swapper);
        }
    }

    /// @notice Backward-compatible alias.
    function setDepositor(address _swapper) external onlyLockerOwner {
        setSwapper(_swapper);
    }

    function _syncSwapperApprovals(address _swapper) internal {
        // tracked tokens first (historical balances may remain unswapped)
        uint256 trackedLength = trackedTokens.length;
        for (uint256 i = 0; i < trackedLength; ++i) {
            _ensureSwapperApproval(trackedTokens[i], _swapper);
        }

        // current active tokens
        (address[] memory tokens, ) = ybDistributor.preview_distribution(0);

        uint256 length = tokens.length;

        for (uint256 i = 0; i < length; ++i) {
            address token = tokens[i];
            if (!_isSwappableToken(token)) continue;
            _ensureSwapperApproval(token, _swapper);
        }
    }

    function _ensureSwapperApproval(address token, address _swapper) internal {
        if (!isTracked[token]) {
            isTracked[token] = true;
            trackedTokens.push(token);
            emit TokenTracked(token);
        }

        uint256 allowance = IERC20(token).allowance(address(this), _swapper);
        if (allowance < type(uint256).max / 2) {
            IERC20(token).forceApprove(_swapper, type(uint256).max);
            emit SwapperApprovalSet(token, _swapper, type(uint256).max);
        }
    }

    function trackedTokensLength() external view returns (uint256) {
        return trackedTokens.length;
    }

    /// @notice Preview raw swap outputs for selected tokens using this contract's current balances.
    /// @dev No haircut is applied; caller should apply slippage buffer off-chain.
    function previewSwaps(address[] calldata tokensToSwapInput) external view returns (address[] memory tokensToSwap, uint256[] memory quotedOuts) {
        address _swapper = swapper;
        require(_swapper != address(0), "swapper not set");

        uint256 inputLength = tokensToSwapInput.length;
        address[] memory unique = new address[](inputLength);
        uint256 count;

        for (uint256 i = 0; i < inputLength; ++i) {
            address token = tokensToSwapInput[i];
            if (!_isSwappableToken(token)) continue;

            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount == 0) continue;

            bool seen;
            for (uint256 j = 0; j < count; ++j) {
                if (unique[j] == token) {
                    seen = true;
                    break;
                }
            }
            if (seen) continue;

            unique[count] = token;
            ++count;
        }

        tokensToSwap = new address[](count);
        quotedOuts = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            address token = unique[i];
            uint256 amount = IERC20(token).balanceOf(address(this));
            tokensToSwap[i] = token;
            quotedOuts[i] = IFeeSwapper(_swapper).previewSwap(token, amount);
        }
    }

    /// @notice Claim weekly fees, convert configured yb tokens to CRVUSD, and deposit rewards.
    function convertAndDepositFees(
        uint256 epochCount,
        address[] calldata tokens,
        uint256[] calldata minOuts
    ) external onlyApprovedCallers {
        address _swapper = swapper;
        require(_swapper != address(0), "swapper not set");
        require(tokens.length == minOuts.length, "!len");

        // Keep approvals fresh for active and historical tokens.
        _syncSwapperApprovals(_swapper);

        ybDistributor.claim(address(this), epochCount, false);

        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            address token = tokens[i];
            if (!_isSwappableToken(token)) continue;

            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount == 0) continue;

            _ensureSwapperApproval(token, _swapper);
            uint256 out = IFeeSwapper(_swapper).swap(token, amount, minOuts[i], address(this));
            emit TokenSwapped(token, amount, out);
        }

        _depositCrvUsdToRewards();
    }

    function _depositCrvUsdToRewards() internal {
        uint256 amount = IERC20(CRVUSD).balanceOf(address(this));
        uint256 rewardAmount = IERC20(YVCRVUSD).balanceOf(address(this));
        if (amount != 0) {
            rewardAmount += IERC4626(YVCRVUSD).deposit(amount, address(this));
        }
        if (rewardAmount == 0) return;
        IFeeDistributor(REWARD_DISTRIBUTOR).depositReward(rewardAmount);
    }

    function _isSwappableToken(address token) internal view returns (bool) {
        if (token == address(0)) return false;
        if (token == CRVUSD) return false;
        if (token == YVCRVUSD) return false;
        return true;
    }

    function setApprovedCaller(address _account, bool _approved) external onlyLockerOwner {
        approvedCallers[_account] = _approved;
        emit SetApprovedCaller(_account, _approved);
    }

    function locker() public view returns(address) {
        return IYToken(YTOKEN).locker();
    }
}
