// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {CCSCEngine} from "../src/CCSCEngine.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployCCSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address public targetAddress = 0x6B86680B6f4f106ed05343aFA0eBe744dE0DF6d7; // CCSC Token on other Chain
    uint16 public targetChain = 6; // from https://docs.wormhole.com/wormhole/quick-start/tutorials/hello-wormhole/hello-wormhole-explained

    function run() external returns (CCSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address wethUsdPriceFeed, address wbtcUsdPrice, address weth, address wbtc) = config.activeNetworkConfig();

        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPrice];

        vm.startBroadcast();
        CCSCEngine engine = new CCSCEngine(tokenAddresses, priceFeedAddresses, targetAddress, targetChain);

        vm.stopBroadcast();
        return (engine, config);
    }
}
