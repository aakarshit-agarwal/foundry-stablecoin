// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Aakarshit Agarwal
 * @notice
 */
contract DSCEngine is ReentrancyGuard {
    //////////////////
    // Errors
    //////////////////
    error DSCEngine__InvalidAmount(uint256 amount);
    error DSCEngine__InvalidLength(
        uint256 tokenLength,
        uint256 priceFeedLength
    );
    error DSCEngine__NotAllowedToken(address tokenAddress);
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();

    //////////////////
    // State Variables
    //////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD_PERCENTAGE = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; // Token to PriceFeed mapping
    mapping(address user => mapping(address token => uint256))
        private s_userCollateralBalances; // User to Token to Collateral Balance mapping
    mapping(address user => uint256 dscMinted) private s_userDscBalances; // User to DSC Balance mapping
    address[] private s_collateralTokens; // List of collateral tokens

    DecentralizedStableCoin private immutable i_dsc;

    //////////////////
    // Events
    //////////////////
    event CollateralDiposited(address user, address token, uint256 amount);

    //////////////////
    // Modifiers
    //////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__InvalidAmount(amount);
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken(tokenAddress);
        }
        _;
    }

    //////////////////
    // Functions
    //////////////////
    constructor(
        address[] memory tokenAddressed,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddressed.length != priceFeedAddresses.length) {
            revert DSCEngine__InvalidLength(
                tokenAddressed.length,
                priceFeedAddresses.length
            );
        }
        // For example ETH / USD, BTC / USD, MKR / USD, etc
        for (uint256 i = 0; i < tokenAddressed.length; i++) {
            s_priceFeeds[tokenAddressed[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddressed[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /////////////////////
    // External Functions
    /////////////////////
    function depositeCollateralAndMintDsc() external {}

    function depositeCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_userCollateralBalances[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDiposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc(
        uint256 amountDscToMint
    ) external moreThanZero(amountDscToMint) nonReentrant {
        s_userDscBalances[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    ////////////////////////////////////
    // Private & Internal View Functions
    ////////////////////////////////////
    function _getAccountInformation(
        address user
    )
        internal
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_userDscBalances[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) internal view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        uint256 collateralAdjustedValueForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD_PERCENTAGE) / 100;
        return
            (collateralAdjustedValueForThreshold * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    ////////////////////////////////////
    // Public & External View Functions
    ////////////////////////////////////
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 collateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; ++i) {
            address token = s_collateralTokens[i];
            uint256 collateralBalance = s_userCollateralBalances[user][token];
            collateralValueInUsd += getUsdValue(token, collateralBalance);
        }
        return collateralValueInUsd;
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
