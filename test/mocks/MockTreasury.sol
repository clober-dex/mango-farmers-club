// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../contracts/interfaces/ITreasury.sol";
import "../../contracts/interfaces/IStakedToken.sol";
import "../../contracts/utils/ReentrancyGuard.sol";

contract MockTreasury is ITreasury, Ownable {
    uint256 private constant _RATE_PRECISION = 1e18;
    uint256 private constant _TOKEN_RATE_PER_SEC = _RATE_PRECISION / 1000 / 1 days; // approximately 0.1% / day

    address public immutable override stakedToken;
    address public immutable override rewardToken;
    uint256 private immutable _rewardTokenDecimalComplement;

    uint256 public override lastDistributedAt;

    constructor(
        address stakedToken_,
        address rewardToken_,
        uint256 startsAt_
    ) {
        stakedToken = stakedToken_;
        rewardToken = rewardToken_;
        _rewardTokenDecimalComplement = 10**(18 - IERC20Metadata(rewardToken).decimals());
        lastDistributedAt = startsAt_;
        setApprovals();
    }

    function setApprovals() public {
        IERC20(rewardToken).approve(stakedToken, type(uint256).max);
    }

    function rewardRate() external pure returns (uint256) {
        return _RATE_PRECISION;
    }

    function getDistributableAmount() public view returns (uint256) {
        uint256 timeDiff = block.timestamp - lastDistributedAt;
        return (_RATE_PRECISION * timeDiff) / _rewardTokenDecimalComplement;
    }

    function receivingToken() external view returns (address) {
        return rewardToken;
    }

    function distribute() public {
        uint256 amount = getDistributableAmount();
        IStakedToken(stakedToken).supplyReward(rewardToken, amount);
        uint256 mLastDistributedAt = lastDistributedAt;
        lastDistributedAt = block.timestamp;
        emit Distribute(amount, block.timestamp - mLastDistributedAt);
    }

    function receiveToken(uint256 amount) external {
        distribute();
        IERC20(rewardToken).transferFrom(msg.sender, address(this), amount);
        emit Receive(msg.sender, amount);
    }

    function withdrawLostERC20(address token, address to) external onlyOwner {
        if (token == rewardToken) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        IERC20(token).transfer(to, IERC20(token).balanceOf(address(this)));
    }
}
