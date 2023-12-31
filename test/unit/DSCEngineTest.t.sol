// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;

    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;

    address user1 = makeAddr("user1");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant user1_STARTING_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, deployerKey) = config
            .activeNetworkConfig();
        ERC20Mock(weth).mint(user1, user1_STARTING_BALANCE);
    }

    ///////////////////
    // Constructor Test
    ///////////////////
    address[] tokenAddress;
    address[] priceFeedAddress;

    function testDifferentLengthForTokenAndPriceFeeds_Revert() public {
        tokenAddress.push(weth);
        priceFeedAddress.push(wethUsdPriceFeed);
        priceFeedAddress.push(wbtcUsdPriceFeed);

        vm.expectRevert(
            abi.encodeWithSignature(
                "DSCEngine__InvalidLength(uint256,uint256)",
                1,
                2
            )
        );
        new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));
    }

    //////////////////
    // Price Feed Test
    //////////////////
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedEthUsdValue = 30000e18;
        uint256 actualUsdValue = engine.getTokenToUsdValue(weth, ethAmount);
        assertEq(actualUsdValue, expectedEthUsdValue);
    }

    function testGetUsdToTokenValue() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedEthCollateral = 0.05 ether;
        uint256 actualEthCollateralValue = engine.getUsdToTokenValue(
            weth,
            usdAmount
        );
        assertEq(actualEthCollateralValue, expectedEthCollateral);
    }

    ///////////////////////////
    // Deposite Collateral Test
    ///////////////////////////
    function testRevertIfCollateralIsZero() public {
        vm.startPrank(user1);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(
            abi.encodeWithSignature("DSCEngine__InvalidAmount(uint256)", 0)
        );
        engine.depositeCollateral(weth, 0);
        vm.stopPrank();
    }
}
