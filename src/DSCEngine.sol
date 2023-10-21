//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {OracleLib, AggregatorV3Interface} from "./libraries/OracleLib.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

/**
 * reedem = To Exchange for Something of Value
 * here we are not using ethers or bitcoins instead we are using wraped ethes and bitcoins, this means that
 *    we are using erc20 versions of ether and bitcoins these type of coins are called as the wrapped coins
 */

contract DSCEngine is ReentrancyGuard {
    /* Errors */
    error DSCEngine_AddressLengthNotShouldBeZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__ReedemCollateralExceed();
    error DSCEngine__BurningAmountOfDscIsExceed();

    /* state variables */
    using OracleLib for AggregatorV3Interface;

    DecentralizedStableCoin private immutable i_dsc;

    /* Contract variables */
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    /* Tokens data tracking variables */
    uint256 private totalTokensMinted = 0;
    uint256 private totalTokensBurned = 0;
    uint256 private totalCollateralValueInUsd = 0;

    /* Mappings */
    // Mapping of token address to price feed address to find the price of the token
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    // Amount of collateral deposited by user
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    // Amount of DSC minted by user
    mapping(address user => uint256 amount) private s_DSCMinted;
    // Amount of DSC burned by user
    mapping(address user => uint256 amount) private s_DSCBurned;
    // token collateral(weth/wbtc) coins addresses
    address[] private s_collateralTokens;
    // address of all users
    address[] private s_usersArray;

    /* Events */
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    /* Modifiers */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length == 0 || priceFeedAddresses.length == 0) {
            revert DSCEngine_AddressLengthNotShouldBeZero();
        }
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /* ---------------------------- Deposit Functions ------------------------- */

    function depositCollateralAndMintDsc( // deploy + minting of DSC
    address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        address[] memory s_usersArrayMemory = s_usersArray;
        bool userFound = false;
        for (uint256 i = 0; i < s_usersArrayMemory.length; i++) {
            if (msg.sender == s_usersArrayMemory[i]) {
                userFound = true;
            }
        }
        if (!userFound) {
            s_usersArray.push(msg.sender);
        }
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /* ---------------------------- Redeem Collateral Functions ---------------------------- */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        moreThanZero(amountCollateral)
    {
        // for burning the healthFactor is reduced then we can redeem the tokens
        _burnDsc(amountDscToBurn, msg.sender);
        // if we burn the dsc tokens then the health factor is increased and we can get more collateral without breaking the health factor
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        // _redeemcolleteral function. already checks the healthFactor, no need to check again
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        uint256 balanceCollateral = s_collateralDeposited[from][tokenCollateralAddress];
        if (balanceCollateral < amountCollateral) {
            revert DSCEngine__ReedemCollateralExceed();
        }
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        // for the IERC20(tokenCollateralAddress) the msg.sender is the DSCEngine
        // at depositing time the collateral amount is sended to the DSCEnginee
        // while redeem the DSCEngine calls the IERC20(tokenCollateralAddress) contract, so the msg.sender id the DSCEnginee
        // here tokens are redeem from DSCEnginee(from address) -> to address
        // negitive numbers are automatically checked by compile in new versions
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /* ---------------------------- BurnDSC Functions ---------------------------- */

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender);
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf) private {
        uint256 dscBalance = s_DSCMinted[onBehalfOf];
        if (amountDscToBurn > dscBalance) {
            revert DSCEngine__BurningAmountOfDscIsExceed();
        }
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        totalTokensBurned += amountDscToBurn;
        s_DSCBurned[onBehalfOf] += amountDscToBurn;
        bool success = i_dsc.transferFrom(onBehalfOf, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
        // in DecentralizedStableCoin contract owner is the enginee so he can only burn the tokens
        // here msg.sender is the engine, the tokens are sended to engine and we burn tokens
    }

    /* ---------------------------- MintDSC Functions ---------------------------- */

    function mintDsc(uint256 amountDscToMint) public {
        s_DSCMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        totalTokensMinted += amountDscToMint;
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);

        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /* ----------------------------- Helper Functions ---------------------------- */

    function revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            // userHealthFactor => 1e18
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    function _healthFactor(address user) public view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        private
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        return (collateralValueInUsd * LIQUIDATION_THRESHOLD * 1e18) / (LIQUIDATION_PRECISION * totalDscMinted);
        // This means you need to be 200% over-collateralized
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 index = 0; index < s_collateralTokens.length; index++) {
            address token = s_collateralTokens[index];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUSD; // returns total collateral value in USD
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        return _getUsdValue(token, amount); // amount in WEI
    }

    function _getUsdValue(address token, uint256 amount) private view returns (uint256) {
        // amount in WEI , if we want to find `x` amount of value in USD, then we have to pass `xe18`
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION);
        // return ((uint256(price) * 1e10) * amount) / 1e18;
    }

    /* --------------------------- Getter Functions --------------------------- */

    function getTotalCollateralValueInUsd() external view returns (uint256) {
        address[] memory s_usersArrayMemory = s_usersArray;
        address[] memory s_collateralTokensMemory = s_collateralTokens;
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < s_usersArrayMemory.length; i++) {
            for (uint256 j = 0; j < s_collateralTokensMemory.length; j++) {
                uint256 collateralamount = s_collateralDeposited[s_usersArrayMemory[i]][s_collateralTokensMemory[j]];
                totalCollateralValue += getUsdValue(s_collateralTokensMemory[j], collateralamount);
            }
        }
        return totalCollateralValue;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
        // return value is in ethers form
    }

    function getBurnedUserDetails(address user) external view returns (uint256) {
        return s_DSCBurned[user];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getUsersArray() external view returns (address[] memory) {
        return s_usersArray;
    }

    function getCollateralDeposited(address userAddress, address collateralAddress) external view returns (uint256) {
        return s_collateralDeposited[userAddress][collateralAddress];
    }

    function getDSCMinted(address userAddress) external view returns (uint256) {
        return s_DSCMinted[userAddress];
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getTotalTokensOnMarket() external view returns (uint256) {
        return getTotalTokensMinted() - getTotalTokensBurned();
    }

    function getTotalTokensMinted() public view returns (uint256) {
        return totalTokensMinted;
    }

    function getTotalTokensBurned() public view returns (uint256) {
        return totalTokensBurned;
    }
}
