// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStakedToken is IERC20Metadata {
    event Plant(address indexed sender, address indexed user, uint256 amount);
    event Unplant(address indexed user, address indexed to, uint256 amount);
    event Harvest(address indexed user, address indexed token, uint256 amount);
    event DistributeReward(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 rewardPerToken,
        uint256 totalSupply
    );

    struct GlobalRewardSnapshot {
        uint256 rewardPerToken;
        address treasury;
        uint64 timestamp;
    }

    struct UserRewardSnapshot {
        uint256 rewardPerToken;
        uint256 harvestableReward;
    }

    struct HarvestableReward {
        address token;
        uint256 amount;
    }

    function underlyingToken() external view returns (address);

    function rewardToken(uint256 index) external view returns (address);

    function rewardTokens() external view returns (address[] memory);

    function rewardTokensLength() external view returns (uint256);

    function globalRewardSnapshot(address token) external view returns (GlobalRewardSnapshot memory);

    function userRewardSnapshot(address user, address token) external view returns (UserRewardSnapshot memory);

    function harvestableRewards(address user) external view returns (HarvestableReward[] memory);

    function harvestableRewards(
        address user,
        address[] calldata tokenList
    ) external view returns (HarvestableReward[] memory);

    function plant(uint256 amount, address to) external;

    function unplant(uint256 amount, address to) external;

    function harvest(address user) external;

    function harvest(address user, address[] calldata tokenList) external;

    function supplyReward(address rewardToken, uint256 amount) external;

    function addRewardToken(address rewardToken, address treasury) external;

    function withdrawLostERC20(address token, address to) external;
}
