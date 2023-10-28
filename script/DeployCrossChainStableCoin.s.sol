// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {CrossChainStableCoin} from "../src/CrossChainStableCoin.sol";

contract DeployCrossChainStableCoin is Script {
    function run() external returns (CrossChainStableCoin) {
        vm.startBroadcast();
        CrossChainStableCoin ccsc = new CrossChainStableCoin();
        vm.stopBroadcast();
        return (ccsc);
    }
}
