# Cross Chain Stable Coin

This project is an exogenously-collateralized cross-chain stablecoin, built from a token contract that is controlled by an "engine" contract. The engine contract utilizes [API3](https://market.api3.org/dapis) for pricefeed data and [Wormhole](https://docs.wormhole.com/wormhole/) for cross chain functionality.

## Table of Contents

- [Cross Chain Stable Coin](#cross-chain-stable-coin)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [CrossChainStableCoin.sol](#crosschainstablecoinsol)
  - [CCSCEngine.sol](#ccscenginesol)
  - [HelperConfig.s.sol](#helperconfigssol)
  - [Installation](#installation)
  - [Deployment](#deployment)
  - [Post Deployment](#post-deployment)
  - [Tx Hash](#tx-hash)
  - [License](#license)

## Overview

This project consists of two contracts deployed across two chains. The first is the `CrossChainStableCoin.sol` contract, which is the CCSC token contract for minting and burning. The second is the `CCSCEngine.sol` contract, which the CCSC token contract through Wormhole. The engine contract uses API3's pricefeed data to secure the algorithmically generated stablecoin. The token contract is deployed on Avalanche Fuji and the engine contract is deployed on Ethereum Goerli.

The Cross Chain Stable Coin keeps its stable price by allowing users to mint an appropriate amount equivalent to their deposit based on API3 oracle prices, and allowing other users to liquidate positions if collateral prices drop too low.

The Cross Chain Stable Coin is exogenously-collateralized because the token used for collateral is not native to the CCSC system and can be from anywhere.

## CrossChainStableCoin.sol

The `CrossChainStableCoin.sol` contract has a `mint()` and a `burn()` function. These functions can only be called by the WormholeRelayer when a message is received from the Engine contract with instructions to mint or burn, a certain amount and the recipient of the action.

[Fuji deployment](https://testnet.snowtrace.io/token/0x6b86680b6f4f106ed05343afa0ebe744de0df6d7?a=0x777452cbc7e71b5286e60ba935292ffd49a597a5)

## CCSCEngine.sol

The `CCSCEngine.sol` contract mints CCSC tokens in exchange for over-collateralized deposits. The CCSC address and collateral get set in the constructor. The CCSCEngine takes in an array of pricefeed addresses that correspond to an array of collateral token addresses. The value of the deposited collateral must be more than the CCSC that is minted in exchange. If the value of the collateral declines based on price data from API3, other users may `liquidate()` a collateralized position to maintain the CCSC token's stable value.

[Goerli deployment](https://goerli.etherscan.io/address/0xE745E8D8eB2c46a7155C599248bC85A11767C8BB#writeContract)

## HelperConfig.s.sol

The HelperConfig script dictates the constructor arguments based on the network being deployed to. The collateral tokens have been set to WETH and WBTC so the pricefeeds we are using are [API3's ETH/USD](https://market.api3.org/dapis/goerli/ETH-USD) and [BTC/USD](https://market.api3.org/dapis/goerli/BTC-USD) feeds.

## Installation

To install the necessary dependencies, first ensure that you have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed by running the following command:

```
curl -L https://foundry.paradigm.xyz | bash
```

Then run the following commands in the project's root directory:

```
foundryup
```

```
forge install
```

## Deployment

You will need to have a `.env` file in each directory with your `$PRIVATE_KEY`.

Replace `$PRIVATE_KEY`, `$GOERLI_RPC_URL` and `$FUJI_RPC_URL` in the `.env` with your respective private key and rpc url.

Deploy the `CrossChainStableCoin.sol` and `CCSCEngine.sol` contracts to their chains by running the following commands:

```
source .env
```

```
forge script script/DeployCrossChainStableCoin.s.sol --private-key $PRIVATE_KEY --rpc-url $FUJI_RPC_URL --broadcast
```

```
forge script script/CCSCEngine.s.sol --private-key $PRIVATE_KEY --rpc-url $GOERLI_RPC_URL --broadcast
```

## Post Deployment

The `setWormholeRelayer()` will have to be called on both contracts with their respective relayer addresses found in the [Wormhole docs](https://docs.wormhole.com/wormhole/blockchain-environments/evm).

## Tx Hash

[tx hash on Goerli](https://goerli.etherscan.io/tx/0x713c2158abf7fc1b5b1fc5c1a6b833ce3b2a3c1fb16218d68b3db96ec68e1b3a)

[tx hash on Fuji](https://testnet.snowtrace.io/tx/0x78ec167a80ff0a367d436f6302b66d26643962c89ee0f951bb23ebe9d487da41)

## License

This project is licensed under the [MIT License](https://opensource.org/license/mit/).
