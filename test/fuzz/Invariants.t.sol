// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Handler} from "./Handler.t.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

contract Invariants is StdInvariant, Test {
    // Handler public handler;
    DeployDSC public deployer;
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    HelperConfig public config;
    address public weth;
    address public wbtc;
    Handler public handler;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMorevalueThanTotalSupply() public view {
        //assert(handler.protocolIsSolvent());
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("WETH Value:", wethValue);
        console.log("WBTC Value:", wbtcValue);
        console.log("Total Supply:", totalSupply);
        console.log("Times Mint Invoked:", handler.timesMintInvoked());
        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getCollateralTokens();
        dscEngine.getAdditionalFeedPrecision();
        dscEngine.getPrecision();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationThreshold();
        dscEngine.getMinHealthFactor();
    }
    function invariant_totalSupplyMatchesDebt() public view {
        //  assert(handler.totalSupplyEqualsTotalDebt());
    }
}
