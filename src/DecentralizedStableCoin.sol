// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    /**
     * Errors
     **/
    error DecentralizedStableCoin__InvalidAmount(uint256 amount);
    error DecentralizedStableCoin__BurnAmountExceedsBalance(
        uint256 amount,
        uint256 balance
    );
    error DecentralizedStableCoin__InvalidAddress(address to);

    constructor() ERC20("Decentralized Stable Coin", "DSC") {}

    function burn(uint256 amount) public override onlyOwner {
        if (amount < 0) {
            revert DecentralizedStableCoin__InvalidAmount(amount);
        }
        uint256 balance = balanceOf(msg.sender);
        if (balance < amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance(
                amount,
                balance
            );
        }
        super.burn(amount);
    }

    function mint(
        address to,
        uint256 amount
    ) external onlyOwner returns (bool) {
        if (to == address(0)) {
            revert DecentralizedStableCoin__InvalidAddress(to);
        }
        if (amount <= 0) {
            revert DecentralizedStableCoin__InvalidAmount(amount);
        }
        _mint(to, amount);
        return true;
    }
}
