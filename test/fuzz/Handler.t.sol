// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    ERC20Mock public weth;
    ERC20Mock public wbtc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    uint256 public constant MAX_DEPOSIT_AMOUNT = type(uint96).max;

    uint256 public timesMintInvoked;
    address[] public usersWithCollateralDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory tokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(tokens[0]);
        wbtc = ERC20Mock(tokens[1]);
        timesMintInvoked = 0;

        ethUsdPriceFeed = dscEngine.getCollateralTokenPriceFeed(address(weth));
        btcUsdPriceFeed = dscEngine.getCollateralTokenPriceFeed(address(wbtc));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_AMOUNT);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }
    // function updateCollateralPrice(uint96 newPrice) public{
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function mintDsc(uint256 amountDsc, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);

        if (maxDscToMint < 0) {
            return;
        }

        amountDsc = bound(amountDsc, 0, uint256(maxDscToMint));
        if (amountDsc == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDsc(amountDsc);
        vm.stopPrank();
        timesMintInvoked += 1;
    }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) internal view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
