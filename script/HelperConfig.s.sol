// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockProxy} from "../test/mocks/MockProxy.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
    }
    // uint256 deployerKey;

    int224 public constant ETH_USD_PRICE = 2000e8;
    int224 public constant BTC_USD_PRICE = 1000e8;
    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 5) {
            activeNetworkConfig = getGoerliEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x26690F9f17FdC26D419371315bc17950a0FC90eD, // ETH/USD feed on Sepolia https://market.api3.org/dapis/sepolia/ETH-USD
            wbtcUsdPriceFeed: 0xe5Cf15fED24942E656dBF75165aF1851C89F21B5, // BTC/USD feed on Sepolia https://market.api3.org/dapis/sepolia/BTC-USD
            weth: 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9,
            wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599
        });
        // deployerKey: vm.envUint("PRIVATE_KEY")
    }

    function getGoerliEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x26690F9f17FdC26D419371315bc17950a0FC90eD, // ETH/USD feed on Sepolia https://market.api3.org/dapis/sepolia/ETH-USD
            wbtcUsdPriceFeed: 0xe5Cf15fED24942E656dBF75165aF1851C89F21B5, // BTC/USD feed on Sepolia https://market.api3.org/dapis/sepolia/BTC-USD
            weth: 0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6,
            wbtc: 0xC04B0d3107736C32e19F1c62b2aF67BE61d63a05
        });
        // deployerKey: vm.envUint("PRIVATE_KEY")
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockProxy wethMockPriceFeed = new MockProxy(ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock();
        MockProxy wbtcMockPriceFeed = new MockProxy(BTC_USD_PRICE);
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(wethMockPriceFeed),
            wbtcUsdPriceFeed: address(wbtcMockPriceFeed),
            weth: address(wethMock),
            wbtc: address(wbtcMock)
        });
        // deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")
    }
}
