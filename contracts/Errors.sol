// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Errors {
    error MangoError(uint256 errorCode);

    uint256 public constant ACCESS = 0;
    uint256 public constant PAUSED = 1;
    uint256 public constant REENTRANCY = 2;
    uint256 public constant INSUFFICIENT_BALANCE = 3;
    uint256 public constant EXCEEDED_BALANCE = 4;
    uint256 public constant SLIPPAGE = 5;
    uint256 public constant AMOUNT_TOO_SMALL = 6;
    uint256 public constant INVALID_ADDRESS = 7;
    uint256 public constant INVALID_TIME = 8;
    uint256 public constant INVALID_FEE = 9;
    uint256 public constant INVALID_BONUS = 10;
}
