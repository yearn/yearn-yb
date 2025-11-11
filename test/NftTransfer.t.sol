// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Setup } from "test/utils/Setup.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract NftTransferTest is Setup {
    address public user = address(0x123);
    address public recipient = address(0x456);

    function setUp() public override {
        super.setUp();
        uint256 lockAmount = 100_000e18;
        uint256 unlockTime = block.timestamp + MAX_LOCK_TIME;
        createLock(user, lockAmount, unlockTime);
        console.log("isPermaLocked", isPermaLocked(user));
        toggleInfiniteLock(user, true);
        toggleInfiniteLock(address(locker), true);
        assertEq(isPermaLocked(user), true, "User is not perma locked");
        assertEq(isPermaLocked(address(locker)), true, "Locker is not perma locked");
    }

    // ============================================
    // NFT Transfer Tests
    // ============================================

    function test_TransferNftMintsYTokens() public {
        uint256 userTokenId = escrow.tokenOfOwnerByIndex(user, 0);
        uint256 recipientBalanceBefore = yToken.balanceOf(recipient);
        uint256 lockedAmountBefore = operator.getLockedAmount();

        // when: User transfers their veYB NFT to the locker
        vm.prank(user);
        IERC721(address(escrow)).safeTransferFrom(
            user,
            address(locker),
            userTokenId,
            abi.encode(recipient) // data
        );
        
        assertGt(yToken.balanceOf(recipient), recipientBalanceBefore);
        assertGt(operator.getLockedAmount(), lockedAmountBefore);
        assertEq(escrow.getVotes(user), 0);
        (int256 amount, ) = escrow.locked(user);
        assertEq(uint256(amount), 0);
    }

    function test_TransferNftRevertsWhenCallerNotEscrow() public {
        // given: A malicious contract tries to call onERC721Received
        uint256 fakeTokenId = 999;
        bytes memory data = abi.encode(recipient);

        // when/then: Direct call to onERC721Received reverts
        vm.expectRevert("Only escrow NFTs");
        vm.prank(user);
        locker.onERC721Received(address(0), user, fakeTokenId, data);
    }

    function test_TransferNftWithZeroRecipientGoesToSender() public {
        uint256 userTokenId = escrow.tokenOfOwnerByIndex(user, 0);
        uint256 balanceBefore = yToken.balanceOf(user);

        // when: User transfers with zero address as recipient
        bytes memory data = abi.encode(address(0));

        vm.prank(user);
        IERC721(address(escrow)).safeTransferFrom(
            user,
            address(locker),
            userTokenId,
            data
        );

        assertGt(yToken.balanceOf(user), balanceBefore);
    }

    function test_TransferNftWithEmptyDataGoesToSender() public {
        uint256 userTokenId = escrow.tokenOfOwnerByIndex(user, 0);
        uint256 balanceBefore = yToken.balanceOf(user);

        // when: User transfers with empty data
        bytes memory data = "";

        vm.prank(user);
        IERC721(address(escrow)).safeTransferFrom(
            user,
            address(locker),
            userTokenId,
            data
        );

        assertGt(yToken.balanceOf(user), balanceBefore);
    }

    function test_TransferNftCallbackRevertsWhenCallerNotLocker() public {
        vm.expectRevert("!locker");
        vm.prank(user);
        operator.nftTransferCallback(user, 123, recipient);
    }

    function test_TransferNftUpdatesOperatorCache() public {
        uint256 userTokenId = escrow.tokenOfOwnerByIndex(user, 0);
        uint256 cachedBefore = operator.cachedLockedAmount();

        // when: User transfers their veYB NFT to the locker
        bytes memory data = abi.encode(recipient);
        vm.prank(user);
        IERC721(address(escrow)).safeTransferFrom(
            user,
            address(locker),
            userTokenId,
            data
        );

        // then: Operator's cached amount is updated
        assertGt(operator.cachedLockedAmount(), cachedBefore);
    }

    function test_TransferNftMintsCorrectAmount() public {
        uint256 userTokenId = escrow.tokenOfOwnerByIndex(user, 0);
        uint256 cachedBefore = operator.cachedLockedAmount();

        // when: User transfers their veYB NFT to the locker
        bytes memory data = abi.encode(recipient);
        vm.prank(user);
        IERC721(address(escrow)).safeTransferFrom(
            user,
            address(locker),
            userTokenId,
            data
        );

        // then: Recipient receives yYB tokens equal to the increase
        uint256 cachedAfter = operator.cachedLockedAmount();
        uint256 expectedMint = cachedAfter - cachedBefore;
        assertEq(yToken.balanceOf(recipient), expectedMint);
    }

    function test_TransferNftAllowsDifferentRecipient() public {
        uint256 userTokenId = escrow.tokenOfOwnerByIndex(user, 0);
        address differentRecipient = address(0x999);

        // when: User transfers with a different recipient
        bytes memory data = abi.encode(differentRecipient);
        vm.prank(user);
        IERC721(address(escrow)).safeTransferFrom(
            user,
            address(locker),
            userTokenId,
            data
        );

        // then: Different recipient receives the yYB tokens, not the user
        assertGt(yToken.balanceOf(differentRecipient), 0);
        assertEq(yToken.balanceOf(user), 0);
    }
}
