// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.12;

import {Script} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DSCCoin} from "src/DSCCoin.sol";

contract DeployDSC is Script {

    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function run() external returns(DSCCoin, DSCEngine, HelperConfig) {

        HelperConfig helperConfig = new HelperConfig();
        (address weth, address wbtc, address wethPriceFeed, address wbtcPriceFeed, uint256 deployer) = helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethPriceFeed, wbtcPriceFeed];
        vm.startBroadcast(deployer);
        DSCCoin dscCoin = new DSCCoin();
        DSCEngine dscEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dscCoin)
        );
        dscCoin.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dscCoin, dscEngine, helperConfig);

    }
    
}