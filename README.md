# DSC Engine

## Table of Contents

- [Introduction](#introduction)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Testing](#testing)
- [Deployment](#deployment)

## Introduction

Project implements a decentralized stablecoin, which is implemented as an ERC20 token, along with an DSCEngine contract. The later is responsible for minting and other keeping the stable price of the token. The structure of the contracts are based on the project suggested by @PatrickAlphaC https://github.com/Cyfrin/foundry-defi-stablecoin-f23. However, some functions have slightly different structure. Also, the testing procedure is carried out by combining the fuzzing, unit and integration tests together.
DSCEngine - https://sepolia.etherscan.io/address/0x06558aee71c06d69e6907b94a1f7a59c36050371#code
DSCCoin - https://sepolia.etherscan.io/address/0x21324f1662d92c001b3aa0493c11062ef2352cd6#code

## Features

- **Minting and Burning**: The DSC Engine allows users to mint and burn DSC stablecoins.
- **Collateral Management**: Users can deposit different types of collateral to back their stablecoins.
- **Health Factor Check**: The system checks the health factor of an account to ensure that the value of the collateral is sufficient to cover the minted stablecoins.
- **Liquidation Rewards**: In case of liquidation, the system calculates the rewards for the liquidator.

## Installation

To get started with the project, clone the repository and install the dependencies with ```forge install ``` command. Then, compile and deploy the contracts using Truffle.

## Basic Usage

1. **Deposit Collateral**: Before you can mint DSC stablecoins, you need to deposit collateral. The type of collateral you can deposit is defined in the HelperConfig contract. By default, these are weth and wbtc tokens. To deposit collateral, call the `depositCollateral` function with the collateral type and the amount you want to deposit as arguments. For example:
````depositCollateral(address _collateralType, uint256 _amount);```

2. **Mint DSC Stablecoins**: After depositing collateral, you can mint DSC stablecoins. The amount of DSC you can mint depends on the amount and type of collateral you have deposited. To mint DSC, call the mintDSC function with the amount you want to mint as the argument. For example:
```mintDSC(uint256 _mintAmount);```

3. **Burn DSC Stablecoins**: If you want to burn your DSC stablecoins, you can call the burnDSC function with the amount you want to burn as the argument. For example:
```burnDSC(uint256 _burnAmount);```

4. **Redeem Collateral**: After burning DSC stablecoins, you can redeem your collateral. To do this, call the redeemCollateral function with the collateral type and the amount you want to redeem as arguments. For example:
```redeemCollateral(address _collateralType, uint256 _amount);```

5. **Check Health Factor**: You can check the health factor of your account at any time by calling the checkHealthFactor function. This function takes the total value of your collateral and the total amount of DSC you have minted as arguments. For example:
```checkHealthFactor(uint256 _collateralValue, uint256 _dscCoinMinted);```

6. **Calculate Liquidation Rewards**: In case of liquidation, you can calculate your rewards by calling the calculateRewards function. This function takes the amount of DSC for liquidation and the type of collateral to reward as arguments. For example:
```calculateRewards(uint256 _amountForLiquidation, address _rewardCollateralType);```

7. **Get Total Collateral Value**: You can get the total value of your collateral by calling the getTotalCollateralValue function with your account address as the argument. For example:
```getTotalCollateralValue(address _user);```


## Testing

Local testing - ```forge test ```
Testing on a fork of a testnet - ```forge test --fork-url ${TESTNET_RPC-URL}```

## Deployment

Local deployment - ```forge script scripts/DeployDSC.sol ```
Deployment on a testnet - ```forge test --rpc-url ${TESTNET_RPC-URL} --private-key ${YOUR_PRIVATE_KEY}```

