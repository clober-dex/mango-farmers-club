// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITokenReceiver {
    /**
     * @notice Emitted when tokens are received.
     * @param sender The address of the sender.
     * @param amount The amount of tokens received.
     */
    event Receive(address indexed sender, uint256 amount);

    /**
     * @notice Returns the address of the receivable token.
     * @return The address of the receivable token.
     */
    function receivingToken() external view returns (address);

    /**
     * @notice Allows the contract to receive tokens.
     * @param amount The amount of tokens to be received.
     */
    function receiveToken(uint256 amount) external;
}
