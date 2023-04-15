// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Errors {
    error MangoError(uint256 errorCode);

    uint256 public constant ACCESS = 0;
    uint256 public constant FAILED_TO_SEND_VALUE = 1;
    uint256 public constant INSUFFICIENT_BALANCE = 2;
    uint256 public constant OVERFLOW_UNDERFLOW = 3;
    uint256 public constant EMPTY_INPUT = 4;
    uint256 public constant INVALID_ADDRESS = 5;
    uint256 public constant INVALID_BONUS = 6;
    uint256 public constant NOT_IMPLEMENTED_INTERFACE = 7;
    uint256 public constant INVALID_FEE = 8;
    uint256 public constant REENTRANCY = 9;
    uint256 public constant INVALID_TIME = 10;
    uint256 public constant SLIPPAGE = 11;
    uint256 public constant AMOUNT_TOO_SMALL = 12;
    uint256 public constant EXCEEDED_BALANCE = 13;
    uint256 public constant INVALID_ID = 14;
    uint256 public constant PAUSED = 15;
    uint256 public constant INVALID_PRICE = 16;
}
