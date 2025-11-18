// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { NFTHelper } from "src/utils/NFTHelper.sol";
import { Protocol, YB, CreateX } from "src/utils/Constants.sol";
import { SafeHelper } from "script/utils/SafeHelper.sol";
import { CreateXHelper } from "script/utils/CreateXHelper.sol";
import { TenderlyHelper } from "script/utils/TenderlyHelper.sol";

contract DeployNFTHelper is Script, SafeHelper, CreateXHelper, TenderlyHelper {

    function run() public isBatch(Protocol.OWNER) {
        deployMode = DeployMode.FORK;
        maxGasPerBatch = 15_000_000;

        if (!isNFTHelperDeployed()) {
            NFTHelper nftHelper = NFTHelper(deployNFTHelper());
            console.log("--- NFTHelper deployed ---");
            console.log("nftHelper:", address(nftHelper));
        }

        if (deployMode == DeployMode.PRODUCTION) executeBatch(true, 0);
    }

    function isNFTHelperDeployed() public view returns (bool) {
        return addressHasCode(Protocol.NFT_HELPER);
    }

    function deployNFTHelper() public returns (address) {
        bytes32 salt = CreateX.SALT_NFTHelper;
        bytes memory constructorArgs = abi.encode(
            YB.GAUGE_CONTROLLER,
            YB.VEYB
        );
        bytes memory bytecode = abi.encodePacked(vm.getCode("NFTHelper.sol:NFTHelper"), constructorArgs);
        addToBatch(
            address(createXFactory),
            encodeCREATE3Deployment(salt, bytecode)
        );
        address deployedAddress = computeCreate3AddressFromSaltPreimage(salt, Protocol.OWNER, true, false);
        require(deployedAddress.code.length > 0, "deployment failed");
        return deployedAddress;
    }
}
