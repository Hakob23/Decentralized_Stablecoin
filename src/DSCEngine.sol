// SPDX-License-Identifier: SEE LICENSE IN LICENSE

pragma solidity ^0.8.12;

import {DSCCoin} from "./DSCCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine {
    error DSCEngine__NonZeroAmount();
    error DSCEngine__CollateralsAndPriceFeedsDontMatch();
    error DSCEngine__CollateralTransferFailed();
    error DSCEngine__WrongCollateralType();
    error DSCEngine__BelowLiquidationThreshold();
    error DSCEngine__StablecoinMintFailed();
    error DSCEngine__CollateralRedeemalFailed();
    error DSCEngine__BurnAmountExceedsTotalMintedBalance();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__CollateralRedeemalAmountExceedsBalance();

    mapping(address user => mapping(address collateral => uint256 amount)) private collateralBalances;
    mapping(address collateral => address priceFeed) private priceFeeds;
    mapping(address user => uint256 mintedAmount) private dscCoinMinted;
    address[] private collateralTypes;
    address private dscCoinAddress;

    uint256 private constant ADDITIONAL_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MIN_HEALTH_FACTOR = 2e18;
    uint256 private constant THRESHOLD_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;

    event CollateralDeposited(address depositor, address collateralType, uint256 amount);
    event CollateralRedeemed(address from, address to, address collateralType, uint256 amount);

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NonZeroAmount();
        }
        _;
    }

    modifier allowedCollateral(address collateralType) {
        if (priceFeeds[collateralType] == address(0)) {
            revert DSCEngine__WrongCollateralType();
        }
        _;
    }

    constructor(address[] memory _collateralTypes, address[] memory _collateralPriceFeeds, address _dscCoinAddress) {
        if (_collateralTypes.length != _collateralPriceFeeds.length) {
            revert DSCEngine__CollateralsAndPriceFeedsDontMatch();
        }
        for (uint256 i = 0; i < _collateralTypes.length; i++) {
            priceFeeds[_collateralTypes[i]] = _collateralPriceFeeds[i];
        }
        collateralTypes = _collateralTypes;
        dscCoinAddress = _dscCoinAddress;
    }

    /////////////////////////////
    /// EXTERNAL FUNCTIONS   ///
    /////////////////////////////

    /// @notice Deposit collateral into the contract and mint DSC
    /// @param _collateralType the address of the collateral token
    /// @param _depositAmount the amount of collateral to deposit
    /// @param _mintAmount the amount of collateral to mint
    function depositCollateralAndMint(address _collateralType, uint256 _depositAmount, uint256 _mintAmount) external {
        depositCollateral(_collateralType, _depositAmount);
        mintDSC(_mintAmount);
    }

    /// @notice burn DSC and redeem collateral from the contract
    /// @param _collateralType the address of the collateral
    /// @param _collateralAmount The amount of Collateral redeemed
    /// @param _dscAmount the amount of dsc burned
    function redeemCollateralAndBurn(address _collateralType, uint256 _collateralAmount, uint256 _dscAmount) external {
        burnDSC(_dscAmount);
        redeemCollateral(_collateralType, _collateralAmount);
    }

    /// @notice Liquidate DSC
    /// @param _account the address of the account to liquidate
    function liquidateDSC(address _account, address _rewardCollateralType, uint256 _amountForLiquidation) external {
        if (calculateHealthFactor(_account) >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        _burnDSC(_account, msg.sender, _amountForLiquidation);
        uint256 rewardAmount = calculateRewards(_amountForLiquidation, _rewardCollateralType);
        _redeemCollateral(_account, msg.sender, _rewardCollateralType, rewardAmount);
    }

    function getTotalMintedDSC(address _user) external view returns (uint256) {
        return dscCoinMinted[_user];
    }

    /////////////////////////////
    /// PUBLIC FUNCTIONS     ///
    /////////////////////////////

    /// @notice Deposit collateral into the contract
    /// @param _collateralType the address of the collateral token
    /// @param _amount the amount of collateral to deposit
    function depositCollateral(address _collateralType, uint256 _amount)
        public
        nonZeroAmount(_amount)
        allowedCollateral(_collateralType)
    {
        collateralBalances[msg.sender][_collateralType] += _amount;
        emit CollateralDeposited(msg.sender, _collateralType, _amount);
        bool success = IERC20(_collateralType).transferFrom(msg.sender, address(this), _amount);
        if (!success) {
            revert DSCEngine__CollateralTransferFailed();
        }
    }

    /// @notice Redeem collateral from the contract
    /// @param _collateralType The address of the collateral token
    /// @param _amount The amount of collateral to redeem
    function redeemCollateral(address _collateralType, uint256 _amount)
        public
        nonZeroAmount(_amount)
        allowedCollateral(_collateralType)
    {
        _redeemCollateral(msg.sender, msg.sender, _collateralType, _amount);
    }

    /// @notice Mint DSC
    /// @param _amount the amount of DSC to mint
    function mintDSC(uint256 _amount) public nonZeroAmount(_amount) returns (bool success) {
        dscCoinMinted[msg.sender] += _amount;
        _revertIfHealthFactorIsBroken(msg.sender);
        success = DSCCoin(dscCoinAddress).mint(msg.sender, _amount);
        if (!success) {
            revert DSCEngine__StablecoinMintFailed();
        }
    }

    /// @notice Burn DSC
    /// @param _amount the amount of DSC to burn
    function burnDSC(uint256 _amount) public nonZeroAmount(_amount) {
        dscCoinMinted[msg.sender] -= _amount;
        _burnDSC(msg.sender, msg.sender, _amount);
    }

    /// @notice Calculate the health factor of an account
    /// @param _minter the address of the account to calculate the health factor
    /// @dev The health factor is calculated as the ratio of the total collateral value to the total DSC minted
    /// @dev The health factor is multiplied by THRESHOLD_PRECISION to avoid floating point arithmetic
    /// @dev The health factor is equal to MIN_HEALTH_FACTOR if no DSC has been minted, to avoid division by zero
    function calculateHealthFactor(address _minter) public view returns (uint256 healthFactor) {
        uint256 totalCollateralValue = getTotalCollateralValue(_minter);
        healthFactor = checkHealthFactor(totalCollateralValue, dscCoinMinted[_minter]);
    }

    /// @notice Get the total collateral value of an account
    /// @param _user the address of the account
    /// @return totalCollateralValue the total collateral value of the account
    function getTotalCollateralValue(address _user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < collateralTypes.length; i++) {
            totalCollateralValue +=
                collateralBalances[_user][collateralTypes[i]] * getPriceFeedValue(collateralTypes[i]);
        }
    }

    /// @notice Calculate the rewards for liquidation
    /// @param _amountForLiquidation the amount of DSC for liquidation
    /// @param _rewardCollateralType the type of collateral to reward
    /// @return the amount of rewards
    function calculateRewards(uint256 _amountForLiquidation, address _rewardCollateralType)
        public
        view
        returns (uint256)
    {
        uint256 rewardAmount = _amountForLiquidation / getPriceFeedValue(_rewardCollateralType);
        uint256 bonusCollateral = rewardAmount * LIQUIDATION_BONUS / THRESHOLD_PRECISION;
        return rewardAmount + bonusCollateral;
    }

    /// @notice Check the health factor
    /// @param _collateralValue the total value of the collateral
    /// @param _dscCoinMinted the total amount of DSC minted
    /// @return healthFactor the health factor of the account
    function checkHealthFactor(uint256 _collateralValue, uint256 _dscCoinMinted)
        public
        pure
        returns (uint256 healthFactor)
    {
        if (_dscCoinMinted == 0) {
            return MIN_HEALTH_FACTOR;
        } else {
            healthFactor = _collateralValue * PRECISION / _dscCoinMinted;
        }
    }

    /// @notice Get the price feed value of a collateral token
    /// @param _collateralType the address of the collateral token
    function getPriceFeedValue(address _collateralType) public view returns (uint256) {
        (, int256 price,,,) = AggregatorV3Interface(priceFeeds[_collateralType]).latestRoundData();
        return uint256(price) * ADDITIONAL_PRECISION / PRECISION;
    }

    /////////////////////////////
    /// PRIVATE FUNCTIONS    ///
    /////////////////////////////

    /// @notice Burn DSC
    /// @param _from the address of the account to burn DSC
    /// @param _amount the amount of DSC to burn
    function _burnDSC(address _from, address _burner, uint256 _amount) private {
        if (dscCoinMinted[_from] < _amount) {
            revert DSCEngine__BurnAmountExceedsTotalMintedBalance();
        }
        dscCoinMinted[_from] -= _amount;
        IERC20(dscCoinAddress).transferFrom(_burner, address(this), _amount);
        DSCCoin(dscCoinAddress).burn(_amount);
    }

    /// @notice Redeem collateral from the contract
    /// @param _from the address of the account to redeem collateral
    /// @param _to the address to send the collateral
    /// @param _collateralType the address of the collateral token
    /// @param _amount the amount of collateral to redeem
    /// @dev The function reverts if the amount exceeds the balance of the account. Can occur if the collateral price changes drastically
    function _redeemCollateral(address _from, address _to, address _collateralType, uint256 _amount) private {
        
        if (collateralBalances[_from][_collateralType] < _amount) {
            revert DSCEngine__CollateralRedeemalAmountExceedsBalance();
        }
        collateralBalances[_from][_collateralType] -= _amount;

        emit CollateralRedeemed(_from, _to, _collateralType, _amount);
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = IERC20(_collateralType).transfer(_to, _amount);
        if (!success) {
            revert DSCEngine__CollateralRedeemalFailed();
        }
    }

    /// @notice Revert if the health factor of an account is below the minimum threshold
    /// @param _minter the address of the account to check the health factor
    function _revertIfHealthFactorIsBroken(address _minter) private view {
        uint256 healthFactor = calculateHealthFactor(_minter);

        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BelowLiquidationThreshold();
        }
    }
}
