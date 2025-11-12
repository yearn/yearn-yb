// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { Locker } from "src/Locker.sol";
import { Operator } from "src/Operator.sol";
import { YLockerToken } from "src/YLockerToken.sol";
import { YB } from "src/utils/Constants.sol";

contract Deploy is Script {
    function run() external returns (Locker, YLockerToken, Operator) {
        vm.startBroadcast();

        Locker locker = new Locker(msg.sender, YB.TOKEN, YB.VEYB);
        YLockerToken yToken = new YLockerToken(address(locker), YB.TOKEN, "Yearn YB Token", "yYB");
        Operator operator = new Operator(payable(address(locker)), YB.GAUGE_CONTROLLER, YB.DAO_VOTING, address(yToken));
        locker.setOperator(address(operator));

        vm.stopBroadcast();
        return (locker, yToken, operator);
    }
}
