// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor(uint256 totalSupply_) ERC20("USD Coin", "USDC") {
        _mint(msg.sender, totalSupply_);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
