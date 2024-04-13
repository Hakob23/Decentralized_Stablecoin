// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.12;

import {Script} from "lib/forge-std/src/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {

    struct NetworkConfig {
        address weth;
        address wbtc;
        address wethPriceFeed;
        address wbtcPriceFeed;
        uint256 deployer;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if(block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getSepoliaConfig() private view returns (NetworkConfig memory) {
        return NetworkConfig({
            weth: 0xE67ABDA0D43f7AC8f37876bBF00D1DFadbB93aaa,
            wbtc: 0x92f3B59a79bFf5dc60c0d59eA13a44D082B2bdFC,
            wethPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployer: vm.envUint("SEPOLIA_KEY")
        });
    }

    function getOrCreateAnvilConfig() private returns (NetworkConfig memory) {

        if(activeNetworkConfig.weth != address(0)) {
            return activeNetworkConfig;
        } else {
            vm.startBroadcast();
            ERC20Mock weth = new ERC20Mock();
            ERC20Mock wbtc = new ERC20Mock();
            MockV3Aggregator wethPriceFeed = new MockV3Aggregator(8, 4_000e8);
            MockV3Aggregator wbtcPriceFeed = new MockV3Aggregator(8, 60_000e8);
            vm.stopBroadcast();
            return NetworkConfig({
            weth: address(weth),
            wbtc: address(wbtc),
            wethPriceFeed: address(wethPriceFeed),
            wbtcPriceFeed: address(wbtcPriceFeed),
            deployer: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        });
        }
        
    }
}