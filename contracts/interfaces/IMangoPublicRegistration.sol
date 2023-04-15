// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMangoPublicRegistration {
    /**
     * @notice Emitted when a deposit is made by a user.
     * @param user The address of the user making the deposit.
     * @param amount The size of the deposit made.
     */
    event Deposit(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a claim is made by a user.
     * @param claimer The address of the user making the claim.
     * @param receiver The address of the receiver of the claim.
     * @param mangoAmount The amount of MANGO tokens claimed.
     * @param usdcRefundAmount The amount of USDC refunded.
     */
    event Claim(address indexed claimer, address indexed receiver, uint256 mangoAmount, uint256 usdcRefundAmount);

    /**
     * @notice Returns the start time of the public registration.
     * @return The start time in unix timestamp.
     */
    function startTime() external view returns (uint256);

    /**
     * @notice Returns the end time of the public registration.
     * @return The end time in unix timestamp.
     */
    function endTime() external view returns (uint256);

    /**
     * @notice Returns the amount deposited by the user.
     * @param user The address of the user to query.
     * @return The amount deposited by the user.
     */
    function depositAmount(address user) external view returns (uint256);

    /**
     * @notice Returns if the user has claimed or not.
     * @param user The address of the user to query.
     * @return If the user has claimed or not.
     */
    function claimed(address user) external view returns (bool);

    /**
     * @notice Returns the current total deposited amount.
     * @return The current total amount deposited amount.
     */
    function totalDeposit() external view returns (uint256);

    /**
     * @notice Allows a user to make a deposit.
     * @param amount The amount to be deposited.
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Allows a user to claim the proceeds of the deposit.
     * @param receiver The address to receive the proceeds.
     */
    function claim(address receiver) external;

    /**
     * @notice Transfers the USDC collected from the event to the treasury.
     * @param usdcReceiver The treasury address to receive the proceeds.
     */
    function transferUSDCToReceiver(address usdcReceiver) external;

    /**
     * @notice Burns the remaining MANGO tokens not sold during the event.
     */
    function burnUnsoldMango() external;
}
