// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    //////////////////
    // State Variables
    //////////////////
    mapping(address token => address priceFeed) private s_priceFeeds; // Token to PriceFeed mapping
    mapping(address user => mapping(address token => uint256))
        private s_userCollateralBalances; // User to Token to Collateral Balance mapping

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
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////
    // External Functions
    //////////////////
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

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
