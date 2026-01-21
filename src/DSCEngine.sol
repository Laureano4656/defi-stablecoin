// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    AggregatorV3Interface
} from "chainlink-brownie-contracts/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
/**
 * @title DSCEngine
 * @author Laureano
 *
 * The system is designed to be as minimal as possible, and havve the tokens maintain a 1:1 peg to USD.
 * This stablecoin has the properties:
 * - Exogenous collateral (ETH & BTC)
 * - Dollar Pegged
 * - Algorithmically stable
 *
 * It is similar to DAI if DAII had no governance, no fees, and only accepted WETH & WBTC as collateral.
 *
 * Our DSC system should always be overcollateralized. At no point should the value of all collateral be less than the value of all DSC.
 * @notice This is the core contract of the DSC system. It handles all the logic for minting and reedeming DSC, as well as depositiing & withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI Stablecoin System).
 */

contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    mapping(address token => address priceFeed) private s_priceFeeds; // token => priceFeed

    DecentralizedStableCoin private immutable i_dsc;

    mapping(address user => mapping(address tokenCollateralAddress => uint256 amountCollateral)) private
        s_collateralDeposited;

    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenCollateralAddress) {
        if (s_priceFeeds[tokenCollateralAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositCollateralAndMintDsc() external {}

    /**
     * @notice Deposits collateral into the DSC system.
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }
    function reedemCollateralForDsc() external {}

    /**
     * @notice Mints DSC to the user.
     * @param amountDscToMint The amount of DSC to mint.
     * @notice Must have more collateral value than the minimum threshold.
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }
    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /*//////////////////////////////////////////////////////////////
                      PRIVATE & INTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        //loop through each collateral token, get the usd value and add them up
        collateralValueInUsd = getAccountCollateralValueInUsd(user);

        return (totalDscMinted, collateralValueInUsd);
    }

    /**
     * @notice Calculates the health factor of a user.
     * @param user The address of the user.
     * @return How close to liquidation the user is.
     */
    function _healthFactor(address user) private view returns (uint256) {
        //get user collateral value
        //get user dsc minted
        //calculate health factor
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 adjustedCollateralValue = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (adjustedCollateralValue * PRECISION) / totalDscMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //get user collateral value
        //get user dsc minted
        //calculate health factor
        //if health factor is less than minimum, revert
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR * PRECISION) {
            revert DSCEngine__BreaksHealthFactor(healthFactor);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      PUBLIC & EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        //loop through each collateral token, get the usd value and add them up
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += (getUsdValue(token, amount));
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256 usdValue) {
        //get the price feed address
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
