// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IWormholeRelayer} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";

contract CrossChainStableCoin is ERC20Burnable, Ownable, IWormholeReceiver {
    error CrossChainStableCoin__MustBeMoreThanZero();
    error CrossChainStableCoin__BurnAmountExceedsBalance();
    error CrossChainStableCoin__NotZeroAddress();
    error CrossChainStableCoin__InvalidRelayer();
    error CrossChainStableCoin__RequestAlreadyProcessed();

    event MintRequested(uint256 amount, uint16 senderChain, address sender);
    event BurnRequested(uint256 amount, uint16 senderChain, address sender);

    enum ActionType {
        MINT, // 0
        BURN // 1
    }

    IWormholeRelayer public wormholeRelayer;

    mapping(bytes32 => bool) public seenDeliveryVaaHashes;

    constructor() ERC20("CrossChainStableCoin", "CCSC") {}

    function burnFrom(address _to, uint256 _amount) private override {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert CrossChainStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert CrossChainStableCoin__BurnAmountExceedsBalance();
        }
        super.burnFrom(_to, _amount);
    }

    function mint(address _to, uint256 _amount) private returns (bool) {
        if (_to == address(0)) {
            revert CrossChainStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert CrossChainStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    function setWormholeRelayer(address _wormholeRelayer) public onlyOwner {
        wormholeRelayer = IWormholeRelayer(_wormholeRelayer);
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32, // address that called 'sendPayloadToEvm'
        uint16 sourceChain,
        bytes32 deliveryHash // this can be stored in a mapping deliveryHash => bool to prevent duplicate deliveries
    ) public payable override {
        if(msg.sender != address(wormholeRelayer)) revert CrossChainStableCoin__InvalidRelayer();
        if(seenDeliveryVaaHashes[deliveryHash]) revert CrossChainStableCoin__RequestAlreadyProcessed();
        seenDeliveryVaaHashes[deliveryHash] = true;

        // Parse the payload and do the corresponding actions!
        (ActionType actionType, uint256 amount, address sender) = abi.decode(payload, (ActionType, uint256, address));

        if (actionType == ActionType.MINT) {
            emit MintRequested(amount, sourceChain, sender);
            mint(sender, amount);
        } else if (actionType == ActionType.BURN) {
            emit BurnRequested(uint256 amount, uint16 senderChain, address sender);
            burnFrom(sender, amount);
        }
    }
}
