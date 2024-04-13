// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.12;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DSCCoin is ERC20Burnable, Ownable {
    error DSCCoin__InsufficientBalance();
    error DSCCoin__NonZeroAmount();

    constructor() ERC20("DSCCoin", "DSC") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (amount == 0) {
            revert DSCCoin__NonZeroAmount();
        }
        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount) public override onlyOwner {
        if (amount > balanceOf(msg.sender)) {
            revert DSCCoin__InsufficientBalance();
        }
        super.burn(amount);
    }
}
