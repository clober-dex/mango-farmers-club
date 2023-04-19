// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ITreasury.sol";
import "./interfaces/IStakedToken.sol";
import "./utils/ReentrancyGuard.sol";
import "./utils/Pausable.sol";

contract MangoTreasury is ITreasury, Initializable, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant _REWARD_RATE_RECIPROCAL = 1000 * 1 days; // approximately 0.1% / day

    address public immutable override stakedToken;
    address public immutable override rewardToken;
    uint256 private immutable _rewardTokenDecimalComplement;

    uint256 public override lastDistributedAt;

    constructor(address stakedToken_, address rewardToken_) {
        stakedToken = stakedToken_;
        rewardToken = rewardToken_;
        _rewardTokenDecimalComplement = 10 ** (18 - IERC20Metadata(rewardToken).decimals());
    }

    function initialize(uint256 startsAt) external initializer {
        _initReentrancyGuard();
        _transferOwnership(msg.sender);
        lastDistributedAt = startsAt;
        setApprovals();
    }

    function setApprovals() public {
        IERC20(rewardToken).safeApprove(stakedToken, 0);
        IERC20(rewardToken).safeApprove(stakedToken, type(uint256).max);
    }

    function rewardRate() external view returns (uint256) {
        return (IERC20(rewardToken).balanceOf(address(this)) * _rewardTokenDecimalComplement) / _REWARD_RATE_RECIPROCAL;
    }

    function getDistributableAmount() public view returns (uint256) {
        if (block.timestamp < lastDistributedAt) {
            return 0;
        }
        uint256 timeDiff = block.timestamp - lastDistributedAt;
        return (IERC20(rewardToken).balanceOf(address(this)) * timeDiff) / _REWARD_RATE_RECIPROCAL;
    }

    function receivingToken() external view returns (address) {
        return rewardToken;
    }

    function distribute() public nonReentrant whenNotPaused {
        if (block.timestamp > lastDistributedAt) {
            uint256 amount = getDistributableAmount();
            uint256 distributeAmount = IStakedToken(stakedToken).supplyReward(rewardToken, amount);
            uint256 mLastDistributedAt = lastDistributedAt;
            lastDistributedAt = block.timestamp;
            emit Distribute(distributeAmount, block.timestamp - mLastDistributedAt);
        }
    }

    function receiveToken(uint256 amount) external {
        distribute();
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        emit Receive(msg.sender, amount);
    }

    function withdrawLostERC20(address token, address to) external onlyOwner {
        if (token == rewardToken) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }
}
