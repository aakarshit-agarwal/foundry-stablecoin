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
    error DSCEngine__HealthFactorIsFine(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsNotImproved();

    //////////////////
    // State Variables
    //////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD_PERCENTAGE = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS_PERCENTAGE = 10;

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
    event CollateralRedeemed(
        address from,
        address to,
        address token,
        uint256 amount
    );

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
    // Constructor
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
    function depositeCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositeCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function depositeCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
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

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // Redeem collateral already checks health factor
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        // Validate health factor > 1
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_userDscBalances[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amountDscToBurn) public {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // This should not be needed
    }

    function liquidate(
        address collateralToLiquidate,
        address userToLiquidate,
        uint256 amountDscToBurn
    ) external moreThanZero(amountDscToBurn) nonReentrant {
        uint256 startingHealthFactor = _healthFactor(userToLiquidate);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsFine(startingHealthFactor);
        }
        // Burn DSC debt
        // And take their collateral + 10% bonus
        uint256 tokenCollateral = getUsdToTokenValue(
            collateralToLiquidate,
            amountDscToBurn
        );
        uint256 bonusCollateral = (tokenCollateral *
            LIQUIDATION_BONUS_PERCENTAGE) / 100;
        uint256 totalCollateral = tokenCollateral + bonusCollateral;
        _redeemCollateral(
            userToLiquidate,
            msg.sender,
            collateralToLiquidate,
            totalCollateral
        );
        _burnDsc(msg.sender, userToLiquidate, amountDscToBurn);
        uint256 endingHealthFactor = _healthFactor(userToLiquidate);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorIsNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

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

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) internal {
        s_userCollateralBalances[from][
            tokenCollateralAddress
        ] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(
        address from,
        address onBehalfOf,
        uint256 amountDscToBurn
    ) internal {
        s_userDscBalances[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(from, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
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
            collateralValueInUsd += getTokenToUsdValue(
                token,
                collateralBalance
            );
        }
        return collateralValueInUsd;
    }

    function getUsdToTokenValue(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getTokenToUsdValue(
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
