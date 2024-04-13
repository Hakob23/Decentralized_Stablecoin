// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.12;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DSCCoin} from "src/DSCCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockV3Aggregator} from "@chainlink/contracts/v0.8/tests/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployDSC;
    HelperConfig helperConfig;
    DSCEngine dscEngine;
    DSCCoin dscCoin;
    address weth;
    address wbtc;
    address wethPriceFeed;
    address wbtcPriceFeed;
    uint256 deployer;

    address public USER;
    address LIQUIDATOR = vm.addr(1);
    uint256 public AMOUNT_COLLATERAL = 10 ether;
    uint256 MIN_HEALTH_FACTOR = 2e18;
    uint256 PRECISION = 1e18;

    modifier depositAmountRestriction(uint256 _depositAmount) {
        vm.assume(
            _depositAmount > 0 && _depositAmount < type(uint256).max / (dscEngine.getPriceFeedValue(weth) * PRECISION)
        );
        if (block.chainid != 31337) {
            vm.assume(IERC20(weth).balanceOf(USER) >= _depositAmount);
        }
        _;
    }

    modifier redeemAmountRestriction(uint256 _redeemAmount, uint256 _depositAmount) {
        vm.assume(_redeemAmount > 0 && _redeemAmount <= _depositAmount);
        _;
    }

    function mockMintAndApprove(uint256 _amount) public {
        
        if(block.chainid == 31337) {
            ERC20Mock(weth).mint(USER, _amount);
        }    
        vm.startPrank(USER);
        IERC20(weth).approve(address(dscEngine), _amount);
    }

    function setUp() external {
        deployDSC = new DeployDSC();
        (dscCoin, dscEngine, helperConfig) = deployDSC.run();
        (weth, wbtc, wethPriceFeed, wbtcPriceFeed, deployer) = helperConfig.activeNetworkConfig();
        USER = vm.addr(deployer);
    }

    //////////////////////////////////////////
    //////////// Constructor Tests ///////////
    //////////////////////////////////////////

    function testRevertsIfaddressLengthsDontMatch() external {
        address[] memory tokenAddresses = new address[](1);
        address[] memory priceFeedAddresses = new address[](2);
        vm.prank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__CollateralsAndPriceFeedsDontMatch.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dscCoin));
    }

    //////////////////////////////////////////
    //////////// Deposit Tests ///////////////
    //////////////////////////////////////////

    function testDepositCollateralRevertsIfZeroAmountIsBeingDeposited() external {

        vm.expectRevert(DSCEngine.DSCEngine__NonZeroAmount.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testDepositCollateralRevertsIfWrongCollateral() external {
        vm.startPrank(USER);
        ERC20Mock newWeth = new ERC20Mock();
        ERC20Mock(newWeth).mint(USER, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__WrongCollateralType.selector);
        dscEngine.depositCollateral(address(newWeth), AMOUNT_COLLATERAL);
    }

    function testDepositCollateralRevertsIfEnoughCollateralHasNotBeenApproved(uint256 _depositAmount) external depositAmountRestriction(_depositAmount){
        uint256 MINIMUM_DEFFICIENCY = 1;
        mockMintAndApprove(_depositAmount - MINIMUM_DEFFICIENCY);
        vm.expectRevert();
        dscEngine.depositCollateral(address(weth), _depositAmount);
        vm.stopPrank();
    }

    function testDepositCollateralChangesCollateralBalance(uint256 _depositAmount)
        external
        depositAmountRestriction(_depositAmount)
    {
        mockMintAndApprove(_depositAmount);
        dscEngine.depositCollateral(weth, _depositAmount);
        vm.stopPrank();
        uint256 collateralValue = _depositAmount * dscEngine.getPriceFeedValue(weth);
        assertEq(dscEngine.getTotalCollateralValue(USER), collateralValue);
    }

    ///////////////////////////////////////////////////////////
    //////////// Mint and HealthFactor Tests //////////////////
    //////////////////////////////////////////////////////////

    function testMintDSCRevertsForMintingZeroAmountDSC() external {
        vm.expectRevert(DSCEngine.DSCEngine__NonZeroAmount.selector);
        vm.prank(USER);
        dscEngine.mintDSC(0);
    }

    function testMintDSCRevertsIfNotEnoughCollateralHasBeenDeposited(uint256 _depositAmount, uint256 _maxAmountToMint)
        external
        depositAmountRestriction(_depositAmount)
    {
        mockMintAndApprove(_depositAmount);
        dscEngine.depositCollateral(weth, _depositAmount);

        uint256 collateralBalance = dscEngine.getTotalCollateralValue(USER);
        console.log(collateralBalance);
        vm.assume(_maxAmountToMint > collateralBalance * PRECISION / MIN_HEALTH_FACTOR);
        vm.expectRevert(DSCEngine.DSCEngine__BelowLiquidationThreshold.selector);
        dscEngine.mintDSC(_maxAmountToMint);
    }

    function testCalculateHealthFactorGeMinHealthFactorIfMintedSuccessfully(uint256 _depositAmount, uint256 _mintAmount)
        external
        depositAmountRestriction(_depositAmount)
    {
        mockMintAndApprove(_depositAmount);
        dscEngine.depositCollateral(weth, _depositAmount);
        uint256 collateralValue = dscEngine.getTotalCollateralValue(USER);
        vm.assume(_mintAmount > 0 && _mintAmount <= collateralValue * PRECISION / MIN_HEALTH_FACTOR);
        dscEngine.mintDSC(_mintAmount);

        vm.stopPrank();

        vm.assertGe(dscEngine.calculateHealthFactor(USER), MIN_HEALTH_FACTOR);
    }

    function testMintDSCUpdatesCollateralAndDscBalancesProperly(
        uint256 _initialAmount,
        uint256 _depositAmount,
        uint256 _mintAmount
    ) external depositAmountRestriction(_depositAmount) {
        vm.assume(_initialAmount > _depositAmount);
        mockMintAndApprove(_initialAmount);
        uint256 initialdepositBalance = IERC20(weth).balanceOf(USER);
        dscEngine.depositCollateral(weth, _depositAmount);
        uint256 collateralValue = dscEngine.getTotalCollateralValue(USER);
        vm.assume(_mintAmount > 0 && _mintAmount <= collateralValue * PRECISION / MIN_HEALTH_FACTOR);
        dscEngine.mintDSC(_mintAmount);
        vm.stopPrank();
        uint256 finalDepositBalance = IERC20(weth).balanceOf(USER);
        vm.assertEq(finalDepositBalance, initialdepositBalance - _depositAmount);
        // vm.assertEq(dscCoin.balanceOf(USER), _mintAmount);
    }

    ///////////////////////////////////////////////////////////
    //////////// BURN TESTS //////////////////////////////////
    //////////////////////////////////////////////////////////

    function testBurnDSCReverts() external {
        vm.expectRevert(DSCEngine.DSCEngine__NonZeroAmount.selector);
        dscEngine.burnDSC(0);
    }

    function testBurnDSC(uint256 _initialAmount, uint256 _depositAmount, uint256 _mintAmount, uint256 _burnAmount)
        external
        depositAmountRestriction(_depositAmount)
    {
        vm.assume(_initialAmount > _depositAmount);
        mockMintAndApprove(_initialAmount);

        dscEngine.depositCollateral(weth, _depositAmount);
        uint256 collateralValue = dscEngine.getTotalCollateralValue(USER);
        vm.assume(_mintAmount > 0 && _mintAmount <= collateralValue * PRECISION / MIN_HEALTH_FACTOR);
        dscEngine.mintDSC(_mintAmount);
        vm.assume(_burnAmount > 0 && _burnAmount <= _mintAmount);
        dscCoin.approve(address(dscEngine), _burnAmount);
        dscEngine.burnDSC(_burnAmount);
        vm.stopPrank();

        vm.assertEq(dscCoin.balanceOf(USER), _mintAmount - _burnAmount);
    }

    function testBurnDSCRevertsIfBurnAmountExceedsMintAmount(
        uint256 _initialAmount,
        uint256 _depositAmount,
        uint256 _mintAmount,
        uint256 _burnAmount
    ) external depositAmountRestriction(_depositAmount) {
        vm.assume(_initialAmount > _depositAmount);
        mockMintAndApprove(_initialAmount);
        dscEngine.depositCollateral(weth, _depositAmount);
        uint256 collateralValue = dscEngine.getTotalCollateralValue(USER);
        vm.assume(_mintAmount > 0 && _mintAmount <= collateralValue * PRECISION / MIN_HEALTH_FACTOR);
        dscEngine.mintDSC(_mintAmount);
        vm.assume(_burnAmount > 0 && _burnAmount > _mintAmount);
        dscCoin.approve(address(dscEngine), _burnAmount);
        vm.expectRevert();
        dscEngine.burnDSC(_burnAmount);
        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////////
    //////////// Redeem Collateral Tests //////////////////////
    //////////////////////////////////////////////////////////

    function testRedeemCollateralRevertsIfRedeemingZeroAmount() external {
        vm.expectRevert(DSCEngine.DSCEngine__NonZeroAmount.selector);
        dscEngine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralRevertsIfRedeemingWrongCollateral() external {
        vm.startPrank(USER);
        ERC20Mock newWeth = new ERC20Mock();
        ERC20Mock(newWeth).mint(USER, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__WrongCollateralType.selector);
        dscEngine.redeemCollateral(address(newWeth), AMOUNT_COLLATERAL);
    }

    function testRedeemCollateralAfterDepositing(uint256 _depositAmount, uint256 _redeemAmount)
        external
        depositAmountRestriction(_depositAmount)
        redeemAmountRestriction(_redeemAmount, _depositAmount)
    {
        mockMintAndApprove(_depositAmount); 
        dscEngine.depositCollateral(weth, _depositAmount);
        uint256 initialBalance = IERC20(weth).balanceOf(USER);
        vm.assertEq(dscEngine.getTotalCollateralValue(USER), _depositAmount * dscEngine.getPriceFeedValue(weth));
        dscEngine.redeemCollateral(weth, _redeemAmount);
        vm.stopPrank();
        uint256 finalBalance = IERC20(weth).balanceOf(USER);
        vm.assertEq(finalBalance, initialBalance + _redeemAmount);
        vm.assertEq(
            dscEngine.getTotalCollateralValue(USER),
            (_depositAmount - _redeemAmount) * dscEngine.getPriceFeedValue(weth)
        );
    }

    function testRedeemCollateralAfterMinting(uint256 _depositAmount, uint256 _mintAmount, uint256 _redeemAmount)
        external
        depositAmountRestriction(_depositAmount)
        redeemAmountRestriction(_redeemAmount, _depositAmount)
        redeemAmountRestriction(_redeemAmount, _depositAmount)
    {
        vm.assume(_mintAmount > 0);
        mockMintAndApprove(_depositAmount);
        dscEngine.depositCollateral(weth, _depositAmount);
        uint256 collateralValue = dscEngine.getTotalCollateralValue(USER);
        vm.assume(_mintAmount > 0 && _mintAmount <= collateralValue * PRECISION / MIN_HEALTH_FACTOR);
        dscEngine.mintDSC(_mintAmount);

        if (
            (collateralValue - _redeemAmount * dscEngine.getPriceFeedValue(weth)) * PRECISION / MIN_HEALTH_FACTOR
                >= _mintAmount
        ) {
            uint256 initialBalance = IERC20(weth).balanceOf(USER);
            dscEngine.redeemCollateral(weth, _redeemAmount);
            uint256 finalBalance = IERC20(weth).balanceOf(USER);
            vm.assertEq(finalBalance, initialBalance + _redeemAmount);
        } else {
            vm.expectRevert(DSCEngine.DSCEngine__BelowLiquidationThreshold.selector);
            dscEngine.redeemCollateral(weth, _redeemAmount);
        }

        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////////
    //////////// depositCollateralAndMint Tests ////////////
    //////////////////////////////////////////////////////////

    function testDepositAndMintCollateral(uint256 _depositAmount, uint256 _mintAmount)
        external
        depositAmountRestriction(_depositAmount)
    {
        vm.assume(_mintAmount > 0);
        mockMintAndApprove(_depositAmount);

        uint256 collateralValue = _depositAmount * dscEngine.getPriceFeedValue(weth);
        uint256 healthFactor = dscEngine.checkHealthFactor(
            collateralValue + dscEngine.getTotalCollateralValue(USER), _mintAmount + dscEngine.getTotalMintedDSC(USER)
        );

        if (healthFactor >= MIN_HEALTH_FACTOR) {
            uint256 initialCollateralBalance = IERC20(weth).balanceOf(USER);
            dscEngine.depositCollateralAndMint(weth, _depositAmount, _mintAmount);
            uint256 finalCollateralBalance = IERC20(weth).balanceOf(USER);
            vm.assertEq(initialCollateralBalance, finalCollateralBalance + _depositAmount);
            vm.assertEq(dscCoin.balanceOf(USER), _mintAmount);
        } else {
            vm.expectRevert(DSCEngine.DSCEngine__BelowLiquidationThreshold.selector);
            dscEngine.depositCollateralAndMint(weth, _depositAmount, _mintAmount);
        }

        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////////
    //////////// redeemCollateralAndBurn() function Tests /////////////
    //////////////////////////////////////////////////////////

    function testRedeemAndBurnCollateral(
        uint256 _depositAmount,
        uint256 _mintAmount,
        uint256 _redeemAmount,
        uint256 _burnAmount
    ) external depositAmountRestriction(_depositAmount) redeemAmountRestriction(_redeemAmount, _depositAmount) {
        vm.assume(_mintAmount > 0);
        mockMintAndApprove(_depositAmount);

        // Deposit and mint collateral

        uint256 collateralValue = _depositAmount * dscEngine.getPriceFeedValue(weth);
        uint256 oldHealthFactor = dscEngine.checkHealthFactor(
            collateralValue + dscEngine.getTotalCollateralValue(USER), _mintAmount + dscEngine.getTotalMintedDSC(USER)
        );
        vm.assume(oldHealthFactor >= MIN_HEALTH_FACTOR);
        dscEngine.depositCollateralAndMint(weth, _depositAmount, _mintAmount);

        // Redeem and burn collateral
        vm.assume(_burnAmount > 0 && _burnAmount <= _mintAmount);
        uint256 redeemCollateralValue = _redeemAmount * dscEngine.getPriceFeedValue(weth);
        uint256 newHealthFactor = dscEngine.checkHealthFactor(
            dscEngine.getTotalCollateralValue(USER) - redeemCollateralValue,
            dscEngine.getTotalMintedDSC(USER) - _burnAmount
        );

        dscCoin.approve(address(dscEngine), _burnAmount);

        if (newHealthFactor >= MIN_HEALTH_FACTOR) {
            dscEngine.redeemCollateralAndBurn(weth, _redeemAmount, _burnAmount);
        } else {
            vm.expectRevert(DSCEngine.DSCEngine__BelowLiquidationThreshold.selector);
            dscEngine.redeemCollateralAndBurn(weth, _redeemAmount, _burnAmount);
        }

        vm.stopPrank();
    }

    function testLiquidateDSCRevertsIfHealthFactorOk(uint256 _depositAmount, uint256 _mintAmount,
    uint256 _redeemAmount, uint256 _burnAmount, uint256 _liquidatedAmount) external depositAmountRestriction(_depositAmount)
    redeemAmountRestriction(_redeemAmount, _depositAmount) {
        vm.assume(_mintAmount > 0);
        mockMintAndApprove(_depositAmount);

        // Deposit and mint collateral

        uint256 collateralValue = _depositAmount * dscEngine.getPriceFeedValue(weth);
        uint256 oldHealthFactor = dscEngine.checkHealthFactor(
            collateralValue + dscEngine.getTotalCollateralValue(USER), _mintAmount + dscEngine.getTotalMintedDSC(USER)
        );
        vm.assume(oldHealthFactor >= MIN_HEALTH_FACTOR);
        dscEngine.depositCollateralAndMint(weth, _depositAmount, _mintAmount);

        // Redeem and burn collateral
        vm.assume(_burnAmount > 0 && _burnAmount <= _mintAmount);
        uint256 redeemCollateralValue = _redeemAmount * dscEngine.getPriceFeedValue(weth);
        uint256 newHealthFactor = dscEngine.checkHealthFactor(
            dscEngine.getTotalCollateralValue(USER) - redeemCollateralValue,
            dscEngine.getTotalMintedDSC(USER) - _burnAmount
        );
        vm.assume(newHealthFactor >= MIN_HEALTH_FACTOR);
        dscCoin.approve(address(dscEngine), _burnAmount);
        dscEngine.redeemCollateralAndBurn(weth, _redeemAmount, _burnAmount);
        vm.stopPrank();

        vm.prank(vm.addr(1));
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        dscEngine.liquidateDSC(USER, weth, _liquidatedAmount);
    }

    function testLiquidateDSC(uint256 _depositAmount, uint256 _mintAmount, uint256 _liquidatedAmount, uint256 _dropPrice) external depositAmountRestriction(_depositAmount) {
        
        // Setting up the initial conditions

        _dropPrice = bound(_dropPrice, 1e8, 4_000e8);
        _mintAmount = bound(_mintAmount, _depositAmount, _depositAmount * 10_000);
        console.log("MintAmount", _mintAmount);
        _liquidatedAmount = bound(_liquidatedAmount, 1, _mintAmount);
        mockMintAndApprove(_depositAmount);
        
        // Deposit and mint collateral

        // Assume that the health factor is above the minimum health factor
        uint256 collateralValue = _depositAmount * dscEngine.getPriceFeedValue(weth);
        uint256 oldHealthFactor = dscEngine.checkHealthFactor(collateralValue, _mintAmount);
        vm.assume(oldHealthFactor >= MIN_HEALTH_FACTOR);


        dscEngine.depositCollateralAndMint(weth, _depositAmount, _mintAmount);
        dscCoin.transfer(LIQUIDATOR, _liquidatedAmount);

        vm.stopPrank();

        // Price goes down
        // As update of the price feed on a real chain is not practical, we will only test this on the local chain
        if (block.chainid != 31337) {
            return;
        }

        MockV3Aggregator(wethPriceFeed).updateAnswer(int(_dropPrice));
       
        uint256 healthFactor = dscEngine.calculateHealthFactor(USER);
        
        vm.assume(healthFactor < MIN_HEALTH_FACTOR);

        vm.startPrank(LIQUIDATOR);
        uint256 rewardAmount = dscEngine.calculateRewards(_liquidatedAmount, weth);
        dscCoin.approve(address(dscEngine), _liquidatedAmount);
        if (_depositAmount < rewardAmount) {
            vm.expectRevert(DSCEngine.DSCEngine__CollateralRedeemalAmountExceedsBalance.selector);
            dscEngine.liquidateDSC(USER, weth, _liquidatedAmount);
        } else{
            dscEngine.liquidateDSC(USER, weth, _liquidatedAmount);
            vm.assertEq(IERC20(weth).balanceOf(LIQUIDATOR), rewardAmount);
        }
        
        
        
    }

}
