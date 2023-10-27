// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {WormholeRelayerSDK} from "@wormhole-solidity-sdk/WormholeRelayerSDK.sol";

contract CrossChainStableCoin is ERC20Burnable, Ownable {
    error CrossChainStableCoin__MustBeMoreThanZero();
    error CrossChainStableCoin__BurnAmountExceedsBalance();
    error CrossChainStableCoin__NotZeroAddress();

    constructor(address _wormholeRelayer, address _tokenBridge, address _wormhole)
        // TokenBase(_wormholeRelayer, _tokenBridge, _wormhole)
        ERC20("CrossChainStableCoin", "CCSC")
    {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert CrossChainStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert CrossChainStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert CrossChainStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert CrossChainStableCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        // sendTokensToAnotherChain()
        return true;
    }

    // // Function to send minted tokens across chains
    // function sendTokensToAnotherChain(address _token, uint256 _amount, uint16 _targetChain, address _targetAddress)
    //     internal
    //     onlyOwner
    // {
    //     transferTokens(_token, _amount, _targetChain, _targetAddress);
    // }
}
