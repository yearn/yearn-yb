// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {FeeDepositor} from "src/FeeDepositor.sol";
import {Operator} from "src/Operator.sol";
import {FeeSwapper} from "src/utils/FeeSwapper.sol";
import {CreateX, Protocol} from "src/utils/Constants.sol";
import {SafeHelper} from "script/utils/SafeHelper.sol";
import {CreateXHelper} from "script/utils/CreateXHelper.sol";

contract DeployFees is Script, SafeHelper, CreateXHelper {
    function run() public isBatch(Protocol.OWNER) {
        deployMode = DeployMode.FORK;
        maxGasPerBatch = 15_000_000;

        address keeper = vm.envAddress("FEE_KEEPER");
        require(keeper != address(0), "!keeper");
        require(Protocol.OPERATOR.code.length != 0, "!operator");

        FeeSwapper feeSwapper = FeeSwapper(_deploy(CreateX.SALT_FEE_SWAPPER, vm.getCode("FeeSwapper.sol:FeeSwapper")));
        FeeDepositor feeDepositor =
            FeeDepositor(_deploy(CreateX.SALT_FEE_DEPOSITOR, vm.getCode("FeeDepositor.sol:FeeDepositor")));

        addToBatch(address(feeDepositor), abi.encodeWithSelector(FeeDepositor.setSwapper.selector, address(feeSwapper)));
        addToBatch(Protocol.OPERATOR, abi.encodeWithSelector(Operator.setFeeDepositor.selector, address(feeDepositor)));
        addToBatch(address(feeDepositor), abi.encodeWithSelector(FeeDepositor.setApprovedCaller.selector, keeper, true));

        require(feeDepositor.swapper() == address(feeSwapper), "!swapper config");
        require(Operator(Protocol.OPERATOR).feeDepositor() == address(feeDepositor), "!operator config");
        require(feeDepositor.approvedCallers(keeper), "!keeper config");

        console.log("--- Fee automation deployed ---");
        console.log("feeDepositor", address(feeDepositor));
        console.log("feeSwapper", address(feeSwapper));
        console.log("keeper", keeper);

        if (deployMode == DeployMode.PRODUCTION) executeBatch(true);
    }

    function _deploy(bytes32 salt, bytes memory initCode) internal returns (address) {
        addToBatch(address(createXFactory), encodeCREATE3Deployment(salt, initCode));
        address deployed = computeCreate3AddressFromSaltPreimage(salt, Protocol.OWNER, true, false);
        require(deployed.code.length != 0, "deployment failed");
        return deployed;
    }
}
