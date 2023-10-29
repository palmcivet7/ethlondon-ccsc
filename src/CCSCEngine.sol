// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IProxy} from "@api3/contracts/v0.8/interfaces/IProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IWormholeRelayer} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";

contract CCSCEngine is ReentrancyGuard, Ownable {
    error CCSCEngine__NeedsMoreThanZero();
    error CCSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error CCSCEngine__NotAllowedToken();
    error CCSCEngine__TransferFailed();
    error CCSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error CCSCEngine__MintFailed();
    error CCSCEngine__BurnFailed();
    error CCSCEngine__HealthFactorOk();
    error CCSCEngine__HealthFactorNotImproved();
    error CCSCEngine__NeedsMorePayment();

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus
    uint256 private constant GAS_LIMIT = 1000000;

    mapping(address token => address priceFeed) private s_priceFeeds; // API3 feeds
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountCcscMinted) private s_CCSCMinted;
    address[] private s_collateralTokens;

    IWormholeRelayer private wormholeRelayer;

    address private immutable targetAddress; // CCSC token
    uint16 private targetChain;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert CCSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert CCSCEngine__NotAllowedToken();
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address _targetAddress,
        uint16 _targetChain
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert CCSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        targetAddress = _targetAddress;
        targetChain = _targetChain;
    }

    ////////////////////////////////////
    //////// Cross Chain Functions ////
    //////////////////////////////////

    function requestMintOnTargetChain(uint256 mintAmount, uint256 paymentAmount) private {
        bytes memory payload = abi.encode(uint8(0), mintAmount, msg.sender);
        wormholeRelayer.sendPayloadToEvm{value: paymentAmount}(targetChain, targetAddress, payload, 0, GAS_LIMIT);
    }

    function requestBurnOnTargetChain(uint256 burnAmount, uint256 paymentAmount) private {
        bytes memory payload = abi.encode(uint8(1), burnAmount, msg.sender);
        wormholeRelayer.sendPayloadToEvm{value: paymentAmount}(targetChain, targetAddress, payload, 0, GAS_LIMIT);
    }

    function setWormholeRelayer(IWormholeRelayer _wormholeRelayer) public onlyOwner {
        wormholeRelayer = _wormholeRelayer;
    }

    function setTargetChain(uint16 _targetChain) public onlyOwner {
        targetChain = _targetChain;
    }

    //////////////////////////////
    //// External Functions /////
    ////////////////////////////

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountCcscToMint The amount of CCSC to mint
     * @notice This function will deposit your collateral and mint CCSC in one transaction
     */
    function depositCollateralAndMintCcsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountCcscToMint
    ) external payable {
        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
        if (msg.value < cost) revert CCSCEngine__NeedsMorePayment();
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        depositCollateral(tokenCollateralAddress, amountCollateral);

        // mintCcsc(amountCcscToMint);

        (bool success,) =
            address(this).call{value: cost}(abi.encodeWithSelector(this.mintCcsc.selector, amountCcscToMint));
        if (!success) revert CCSCEngine__MintFailed();
    }

    /**
     * @notice follows CEI (Checks, Effects, Interaction)
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) public 
    // isAllowedToken(tokenCollateralAddress)
    // moreThanZero(amountCollateral)
    // nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert CCSCEngine__TransferFailed();
        }
    }

    /**
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountCcscToBurn The amount of CCSC to burn
     * This function burns CCSC and redeems the underlying collateral in one transaction
     */
    function redeemCollateralForCcsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountCcscToBurn)
        external
        payable
    {
        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
        if (msg.value < cost) revert CCSCEngine__NeedsMorePayment();
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        (bool success,) =
            address(this).call{value: cost}(abi.encodeWithSelector(this.burnCcsc.selector, amountCcscToBurn));
        if (!success) revert CCSCEngine__BurnFailed();

        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    // In order to redeem collateral:
    // 1. Health factor must be over 1 AFTER collateral pulled
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Follows CEI
     * @param amountCcscToMint The amount of CCSC to mint
     * @notice User must have more collateral value than the minimum threshold
     */
    function mintCcsc(uint256 amountCcscToMint) public payable moreThanZero(amountCcscToMint) nonReentrant {
        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
        if (msg.value < cost) revert CCSCEngine__NeedsMorePayment();
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        s_CCSCMinted[msg.sender] += amountCcscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        requestMintOnTargetChain(amountCcscToMint, cost);
    }

    function burnCcsc(uint256 amount) public payable moreThanZero(amount) {
        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
        if (msg.value < cost) revert CCSCEngine__NeedsMorePayment();
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }

        _revertIfHealthFactorIsBroken(msg.sender);
        _burnCcsc(amount, msg.sender, cost);
    }

    /**
     * @param collateral The ERC20 collateral address to liquidate from the user
     * @param user The user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FAT
     * @param debtToCover The amount of CCSC you want to burn to improve the users health factor
     * @notice You can partially liquid a user.
     * @notice You will get a liquidation bonus for taking the users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        payable
        moreThanZero(debtToCover)
        nonReentrant
    {
        (uint256 cost,) = wormholeRelayer.quoteEVMDeliveryPrice(targetChain, 0, GAS_LIMIT);
        if (msg.value < cost) revert CCSCEngine__NeedsMorePayment();
        if (msg.value > cost) {
            payable(msg.sender).transfer(msg.value - cost);
        }
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert CCSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnCcsc(debtToCover, user, cost);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert CCSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////////////////////////////
    //// Private & Internal View Functions /////
    ///////////////////////////////////////////

    /**
     * @dev Low-level internal function -
     * Do not call unless the function calling it is checking for health factors being broken.
     */
    function _burnCcsc(uint256 amountCcscToBurn, address onBehalfOf, uint256 paymentAmount) private {
        s_CCSCMinted[onBehalfOf] -= amountCcscToBurn;
        requestBurnOnTargetChain(amountCcscToBurn, paymentAmount);
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert CCSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalCcscMinted, uint256 collateralValueInUsd)
    {
        totalCcscMinted = s_CCSCMinted[user];
        collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /**
     * Returns how close to liquidation a user is.
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalCcscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalCcscMinted, collateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert CCSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _calculateHealthFactor(uint256 totalCcscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalCcscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalCcscMinted;
    }

    /////////////////////////////////////////////
    //// Public & External View Functions //////
    ///////////////////////////////////////////

    function calculateHealthFactor(uint256 totalCcscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalCcscMinted, collateralValueInUsd);
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        (int224 value,) = IProxy(s_priceFeeds[token]).read();
        return (usdAmountInWei * PRECISION) / (uint256(uint224(value)) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        (int224 value,) = IProxy(s_priceFeeds[token]).read();
        return ((uint256(uint224(value)) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalCcscMinted, uint256 collateralValueInUsd)
    {
        (totalCcscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getPriceFeedForToken(address token) public view returns (address) {
        return s_priceFeeds[token];
    }

    function getCollateralTokenAtIndex(uint256 index) public view returns (address) {
        return s_collateralTokens[index];
    }

    function getCollateralTokensLength() public view returns (uint256) {
        return s_collateralTokens.length;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
