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

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user1 = address(1);
    address public user2 = address(2);
    address public user3 = address(3);

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
    
        // after deploying all contrcats and setting all the variables we minting the tokens for user1
        ERC20Mock(weth).mint(user1, STARTING_USER_BALANCE);   // user1 have 10 wrapped ethers
        ERC20Mock(wbtc).mint(user1, STARTING_USER_BALANCE);   // user1 have 10 wrapped bitcoins
    }

    function test_SetUpCheckStatus() public {
        assertEq(ERC20Mock(weth).balanceOf(user1), STARTING_USER_BALANCE);
        assertEq(ERC20Mock(wbtc).balanceOf(user1), STARTING_USER_BALANCE);
        assertEq(helperConfig.DEFAULT_ANVIL_PRIVATE_KEY(), deployerKey);  
        // by default we deploy on the anvil network
        assertEq(ERC20Mock(weth).totalSupply(), ERC20Mock(weth).balanceOf(user1));
        assertEq(ERC20Mock(wbtc).totalSupply(), ERC20Mock(wbtc).balanceOf(user1));
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
        assertEq(dsce.getTokenAmountFromUsd(weth,usdAmountInWeiForEth), expectedEthAmount);
        assertEq(dsce.getTokenAmountFromUsd(wbtc,usdAmountInWeiForBtc), expectedBtcAmount);
    }

    function test_getUsdValue() public {
        uint256 ethAmount = 2 ether;
        uint256 expectedUsdValue1 = 4000 * 10 ** 18;
        assertEq(dsce.getUsdValue(weth, ethAmount), expectedUsdValue1);
        
        uint256 btcAmount = 2 ether;
        uint256 expectedUsdValue2 = 50000 * 10 ** 18;
        assertEq(dsce.getUsdValue(wbtc, btcAmount), expectedUsdValue2);
    }

    /* Depositing colleteral of 10 ethers and 10 bitcoins */
    function depositCollateral(uint256 amount) public {
        // to transfer the coins first we have to approve the dsce contract to receive
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        ERC20Mock(wbtc).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth,amount); // 20000$ USD
        dsce.depositCollateral(wbtc,amount); // 250000$ USD
        // 270000$ - total collateral in USD
    }

    /* Testing total collateral amount value in usd after depositing collateral(eth, wth) into dsce engine */
    function test_getAccountCollateralValueInUsdOfUser() public {
        uint256 beforeDepositingCollateral = dsce.getAccountCollateralValue(user1);
        assertEq(beforeDepositingCollateral, 0);
        vm.startPrank(user1);
        depositCollateral(10); 
        vm.stopPrank();
        uint256 expectedTotalCollateralAmountInUsd = 270000;
        assertEq(dsce.getAccountCollateralValue(user1), expectedTotalCollateralAmountInUsd);
    }
  
    /* Testing health factor of a user */
    function test_CheckingHealthFactorBeforeNotMintedDscCoins() public {
        assertEq(dsce._healthFactor(user1), type(uint).max); 
    }

    function test_FailingHealthFactorWhileMintingTokens() public {
        vm.startPrank(user1);
        depositCollateral(10);
        uint256 expectedHealthFactor = dsce._healthFactor(user1);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        dsce.mintDsc(270000);
        vm.stopPrank(); // 100,000000000000000000
    }
}