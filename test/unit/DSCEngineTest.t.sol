// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract DSCEngineTest is StdCheats, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    address public user1 = address(1);
    address public user2 = address(2);
    address public user3 = address(3);

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        // after deploying all contracts and setting all the variables we minting the tokens for user1
        ERC20Mock(weth).mint(user1, STARTING_USER_BALANCE); // user1 have 10 wrapped ethers
        ERC20Mock(wbtc).mint(user1, STARTING_USER_BALANCE); // user1 have 10 wrapped bitcoins
        ERC20Mock(weth).mint(user2, STARTING_USER_BALANCE); // user1 have 10 wrapped ethers
        ERC20Mock(wbtc).mint(user2, STARTING_USER_BALANCE); // user1 have 10 wrapped bitcoins
    }

    /* ------------------------------- Helper funcions ------------------------------- */
    function depositCollateralAmount(uint256 amountCollateral) public {
        // to transfer the coins first we have to approve the dsce contract to receive
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        ERC20Mock(wbtc).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral); // 20000$ USD
        dsce.depositCollateral(wbtc, amountCollateral); // 250000$ USD
            // 270000$ - total collateral in USD
    }

    /* ------------------------ checking constructor values data -------------------------- */
    function test_SetUpCheckStatus() public {
        assertEq(ERC20Mock(weth).balanceOf(user1), STARTING_USER_BALANCE);
        assertEq(ERC20Mock(wbtc).balanceOf(user1), STARTING_USER_BALANCE);
        assertEq(helperConfig.DEFAULT_ANVIL_PRIVATE_KEY(), deployerKey);
        // by default we deploy on the anvil network
        uint256 wethBalance = ERC20Mock(weth).balanceOf(user1) + ERC20Mock(weth).balanceOf(user2);
        uint256 wbtcBalance = ERC20Mock(wbtc).balanceOf(user1) + ERC20Mock(wbtc).balanceOf(user2);
        assertEq(ERC20Mock(weth).totalSupply(), wethBalance);
        assertEq(ERC20Mock(wbtc).totalSupply(), wbtcBalance);
    }

    /* Constructor testing */
    address[] public tokenAddresses;
    address[] public feedAddresses;

    function test_RevertsIfNullAddressAreGiven() public {
        vm.expectRevert(DSCEngine.DSCEngine_AddressLengthNotShouldBeZero.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    function test_RevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        feedAddresses.push(ethUsdPriceFeed);
        feedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    /* converting price to tokens and tokens to price Testing */
    function test_getTokenAmountFromUsd() public {
        uint256 usdAmountInWeiForEth = 30000;
        uint256 usdAmountInWeiForBtc = 50000;
        // 1 ether = 2000$
        // for 30000$ USD we get 15 ethers
        // 1 btc = 25000$
        // for 50000$ USD we get 2 bitcoins
        uint256 expectedEthAmount = 15;
        uint256 expectedBtcAmount = 2;
        assertEq(dsce.getTokenAmountFromUsd(weth, usdAmountInWeiForEth), expectedEthAmount);
        assertEq(dsce.getTokenAmountFromUsd(wbtc, usdAmountInWeiForBtc), expectedBtcAmount);
    }

    function test_getUsdValue() public {
        uint256 ethAmount = 2 ether;
        uint256 expectedUsdValue1 = 2 * 2000 * 10 ** 18;
        assertEq(dsce.getUsdValue(weth, ethAmount), expectedUsdValue1);

        uint256 btcAmount = 2 ether;
        uint256 expectedUsdValue2 = 2 * 25000 * 10 ** 18;
        assertEq(dsce.getUsdValue(wbtc, btcAmount), expectedUsdValue2);
    }

    /* Testing total collateral amount value in usd after depositing collateral(eth, wth) into dsce engine */
    function test_getAccountCollateralValueInUsdOfUser() public {
        uint256 beforeDepositingCollateral = dsce.getAccountCollateralValue(user1);
        assertEq(beforeDepositingCollateral, 0);
        vm.startPrank(user1);
        depositCollateralAmount(10);
        vm.stopPrank();
        uint256 expectedTotalCollateralAmountInUsd = 270000;
        assertEq(dsce.getAccountCollateralValue(user1), expectedTotalCollateralAmountInUsd);
    }

    /* Testing health factor of a user */
    function test_CheckingHealthFactorBeforeNotMintedDscCoins() public {
        assertEq(dsce._healthFactor(user1), type(uint256).max);
    }

    function test_breakingHealthFactorWhileMintingMoreTokens() public {
        vm.startPrank(user1);
        depositCollateralAmount(10);
        uint256 expectedHealthFactor = 999992592647461870;
        // (270000 * 50 * 1e18) / (135001 * 100);
        // => 999992592647461870 > 1000000000000000000 => false
        // here we deposit 270,000 $ value of collateral, by calculating thresold we can only mint 13500 tokens
        // if we try to mint 135001 tokens the health factor is broken
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));// 999992592647461870
        dsce.mintDsc(135001);  
        vm.stopPrank();
    }

    /* testing helper functions */
    function test_DscAdddress() public {
        assertEq(dsce.getDsc(),address(dsc));
    }

    /* Deposting and minting tokens for testing correct data */
    function test_depositingAndMintingFunctions() public {
        uint256 beforeCollateralValueInUsd = 0;
        assertEq(dsce.getTotalCollateralValueInUsd(), beforeCollateralValueInUsd);
        
        uint256 user1CollateralValue = 270000;
        vm.startPrank(user1);  // depositing collateral value of 270,000$ by user1
        depositCollateralAmount(10);  // 20000 + 250000 = 270000$ USD
        vm.stopPrank();

        uint256 user2CollateralValue = 135000;
        vm.startPrank(user2); // depositing collateral value of 135,000$ by user2
        depositCollateralAmount(5);  // 10000 + 125000 = 135000$ USD
        vm.stopPrank();

        uint256 afterCollateralValueInUsd = user1CollateralValue + user2CollateralValue;
        assertEq(dsce.getTotalCollateralValueInUsd(), afterCollateralValueInUsd);

        uint256 amountToMint = 5000;
        uint256 ExpectedBurnedTokens = 0;
        vm.startPrank(user1);
        dsce.mintDsc(amountToMint);
        vm.stopPrank();

        assertEq(dsce.getTotalTokensMinted(), amountToMint);
        assertEq(dsce.getTotalTokensOnMarket(), amountToMint);
        assertEq(dsce.getTotalTokensBurned(), ExpectedBurnedTokens);
        assertEq(dsce.getTotalCollateralValueInUsd(), afterCollateralValueInUsd);

        assertEq(dsce.getDSCMinted(user1), amountToMint);
        assertEq(dsce.getAccountCollateralValue(user1), user1CollateralValue);

        // checking health factor after minting tokens
        // (270000 * 50 * 1e18) / (100 * 5000) = 27000000000000000000
        uint256 expectedHealthFactor = 27000000000000000000;
        assertEq(dsce._healthFactor(user1), expectedHealthFactor);
        assertEq(dsce._healthFactor(user2), type(uint256).max);
    }

    /* Test buring function */
    function test_burnFunction() public {
        uint256 amountToMint = 1000;
        uint256 amountToBurn = 500;
        vm.startPrank(user2);
        // approving our DscEngine contract to burn the tokens
        DecentralizedStableCoin(dsc).approve(address(dsce), amountToMint);
        depositCollateralAmount(2);
        dsce.mintDsc(amountToMint);
        uint256 healthFactorBeforeBurning = dsce._healthFactor(user2);  // low health factor
        // burning the tokens
        dsce.burnDsc(amountToBurn);
        uint256 healthFactorAfterBurning = dsce._healthFactor(user2);  // high health factor
        vm.stopPrank();

        assertEq(dsce.getTotalTokensBurned(), amountToBurn);
        assertEq(dsce.getTotalTokensMinted(), amountToMint);
        assertEq(dsce.getTotalTokensOnMarket(), amountToMint - amountToBurn);

        assertLt(healthFactorBeforeBurning, healthFactorAfterBurning);
    }

    function test_redeemCollateralFunction() public {
        vm.startPrank(user1);
        depositCollateralAmount(10); // 270000$ USD
        uint256 collateralValueBeforeRedeem = dsce.getAccountCollateralValue(user1);
        uint256 beforeHealthFactor = dsce._healthFactor(user1);

        dsce.redeemCollateral(address(weth), 5);  // 270000 - 10000 = 260000$ USD
        uint256 afterHealthFactor = dsce._healthFactor(user1);
        uint256 collateralValueAfterRedeem = dsce.getAccountCollateralValue(user1);
        uint256 amountToCover = 10000;

        assertEq(collateralValueBeforeRedeem, collateralValueAfterRedeem + amountToCover);
        assertEq(beforeHealthFactor, afterHealthFactor);  
        // here both are same because we do not mint any tokens to change the health factor
        vm.stopPrank();
    }
}
