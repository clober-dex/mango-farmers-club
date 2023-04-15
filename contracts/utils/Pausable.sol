// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../Errors.sol";

abstract contract Pausable is Ownable {
    bool public paused;

    modifier whenNotPaused() {
        if (paused) {
            revert Errors.MangoError(Errors.PAUSED);
        }
        _;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }
}
