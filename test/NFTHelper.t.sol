// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Setup } from "test/utils/Setup.sol";
import { NFTHelper } from "src/utils/NFTHelper.sol";

contract NFTHelperTest is Setup {
    NFTHelper public nftHelper;

    function setUp() public override {
        super.setUp();
        nftHelper = new NFTHelper(address(gaugeController), address(escrow));
    }

    function test_GetTokenIdReturnsAddressAsUint256() public view {
        address user = address(0x1234567890AbcdEF1234567890aBcdef12345678);
        uint256 expected = uint256(uint160(user));
        assertEq(nftHelper.getTokenId(user), expected);
    }

    function test_GetNftTransferInfoWithNoLock() public view {
        address user = address(0x999);
        (
            uint256 tokenId,
            uint256 lockedAmount,
            bool isVotePowerCleared,
            bool isPermanentLock,
            address[] memory votedGauges
        ) = nftHelper.getNftTransferInfo(user);

        assertEq(tokenId, uint256(uint160(user)));
        assertEq(lockedAmount, 0);
        assertTrue(isVotePowerCleared);
        assertFalse(isPermanentLock);
        assertEq(votedGauges.length, 0);
    }

    function test_GetNftTransferInfoWithRegularLock() public {
        address user = address(0x888);
        uint256 amount = 100e18;
        uint256 unlockTime = block.timestamp + 365 days;

        createLock(user, amount, unlockTime);

        (
            uint256 tokenId,
            uint256 lockedAmount,
            bool isVotePowerCleared,
            bool isPermanentLock,
            address[] memory votedGauges
        ) = nftHelper.getNftTransferInfo(user);

        assertEq(tokenId, uint256(uint160(user)));
        assertApproxEqAbs(lockedAmount, amount, 1e10);
        assertTrue(isVotePowerCleared);
        assertFalse(isPermanentLock);
        assertEq(votedGauges.length, 0);
    }

    function test_GetNftTransferInfoWithPermanentLock() public {
        address user = address(0x777);
        uint256 amount = 100e18;
        uint256 unlockTime = block.timestamp + 365 days;

        createLock(user, amount, unlockTime);
        toggleInfiniteLock(user, true);

        (
            uint256 tokenId,
            uint256 lockedAmount,
            bool isVotePowerCleared,
            bool isPermanentLock,
            address[] memory votedGauges
        ) = nftHelper.getNftTransferInfo(user);

        assertEq(tokenId, uint256(uint160(user)));
        assertApproxEqAbs(lockedAmount, amount, 1e10);
        assertTrue(isVotePowerCleared);
        assertTrue(isPermanentLock);
        assertEq(votedGauges.length, 0);
    }

    function test_GetNftTransferInfoWithActiveVotes() public {
        // vm.skip(true);

        uint256 nGauges = gaugeController.n_gauges();
        if (nGauges == 0 || nGauges > 100) {
            return;
        }

        address user = address(0x666);
        uint256 amount = 100e18;
        uint256 unlockTime = block.timestamp + 365 days;

        createLock(user, amount, unlockTime);

        address[] memory gaugeAddrs = new address[](2);
        uint256[] memory weights = new uint256[](2);
        uint256 k;

        for (uint256 i = 0; i < nGauges && k < 2; i++) {
            address g = gaugeController.gauges(i);
            if (gaugeController.is_killed(g)) continue;
            gaugeAddrs[k] = g;
            weights[k] = 5000;
            k++;
        }

        vm.prank(user);
        gaugeController.vote_for_gauge_weights(gaugeAddrs, weights);

        bool isVotePowerClearedCheck = gaugeController.ve_transfer_allowed(user);
        assertFalse(isVotePowerClearedCheck);

        (
            uint256 tokenId,
            uint256 lockedAmount,
            bool isVotePowerCleared,
            bool isPermanentLock,
            address[] memory votedGauges
        ) = nftHelper.getNftTransferInfo(user);

        assertEq(tokenId, uint256(uint160(user)));
        assertApproxEqAbs(lockedAmount, amount, 1e10);
        assertFalse(isVotePowerCleared);
        assertFalse(isPermanentLock);
        assertEq(votedGauges.length, gaugeAddrs.length);

        for (uint256 i = 0; i < votedGauges.length; i++) {
            assertEq(votedGauges[i], gaugeAddrs[i]);
        }
    }
}
