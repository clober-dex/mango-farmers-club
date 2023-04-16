// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IStakedToken.sol";
import "./interfaces/ITreasury.sol";
import "./utils/ReentrancyGuard.sol";
import "./utils/Pausable.sol";

contract MangoStakedToken is IStakedToken, ERC20, Ownable, Pausable, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant _RATE_PRECISION = 1e27;

    address public immutable override underlyingToken;

    address[] private _rewardTokens;
    // token => snapshot
    mapping(address => GlobalRewardSnapshot) private _globalRewardSnapshot;
    // user => token => snapshot
    mapping(address => mapping(address => UserRewardSnapshot)) private _userRewardSnapshot;

    modifier updateReward(address user) {
        {
            uint256 totalStakedAmount = totalSupply();
            uint256 userBalance = balanceOf(user);
            address[] memory mRewardTokens = _rewardTokens;
            for (uint256 i = 0; i < mRewardTokens.length; ++i) {
                address token = mRewardTokens[i];
                address treasury = _globalRewardSnapshot[token].treasury;
                if (totalStakedAmount > 0 && block.timestamp > ITreasury(treasury).lastDistributedAt()) {
                    ITreasury(treasury).distribute();
                }
                if (user != address(0)) {
                    uint256 globalRewardPerToken = _globalRewardSnapshot[token].rewardPerToken;
                    _userRewardSnapshot[user][token] = UserRewardSnapshot({
                        rewardPerToken: globalRewardPerToken,
                        harvestableReward: _harvestableReward(user, token, globalRewardPerToken, userBalance)
                    });
                }
            }
        }
        _;
    }

    constructor(address underlyingToken_) ERC20("Planted Mango", "pMANGO") {
        underlyingToken = underlyingToken_;
    }

    function initialize(address[] calldata rewardTokens_, address[] calldata treasuries_) external initializer {
        _initReentrancyGuard();
        _transferOwnership(msg.sender);
        for (uint256 i = 0; i < rewardTokens_.length; ++i) {
            // @dev Assume that rewardTokens_ does not have duplicated elements.
            // @dev Assume that the length of two arrays is the same.
            _addRewardToken(rewardTokens_[i], treasuries_[i]);
        }
    }

    function name() public pure override(IERC20Metadata, ERC20) returns (string memory) {
        return "Planted Mango";
    }

    function symbol() public pure override(IERC20Metadata, ERC20) returns (string memory) {
        return "pMANGO";
    }

    function _transfer(address, address, uint256) internal pure override {
        revert Errors.MangoError(Errors.ACCESS);
    }

    function rewardToken(uint256 index) external view returns (address) {
        return _rewardTokens[index];
    }

    function rewardTokens() external view returns (address[] memory) {
        return _rewardTokens;
    }

    function rewardTokensLength() external view returns (uint256) {
        return _rewardTokens.length;
    }

    function globalRewardSnapshot(address token) external view returns (GlobalRewardSnapshot memory) {
        return _globalRewardSnapshot[token];
    }

    function userRewardSnapshot(address user, address token) external view returns (UserRewardSnapshot memory) {
        return _userRewardSnapshot[user][token];
    }

    function harvestableRewards(address user) external view returns (HarvestableReward[] memory) {
        return harvestableRewards(user, _rewardTokens);
    }

    function harvestableRewards(
        address user,
        address[] memory tokenList
    ) public view returns (HarvestableReward[] memory rewardList) {
        rewardList = new HarvestableReward[](tokenList.length);
        uint256 totalStakedAmount = totalSupply();
        uint256 userBalance = balanceOf(user);
        for (uint256 i = 0; i < tokenList.length; ++i) {
            address token = tokenList[i];
            uint256 reward;
            if (totalStakedAmount > 0) {
                GlobalRewardSnapshot memory mGlobalRewardSnapshot = _globalRewardSnapshot[token];
                uint256 distributableAmount = ITreasury(mGlobalRewardSnapshot.treasury).getDistributableAmount();
                uint256 newRewardPerToken = mGlobalRewardSnapshot.rewardPerToken +
                    (distributableAmount * _RATE_PRECISION) /
                    totalStakedAmount;
                reward = _harvestableReward(user, token, newRewardPerToken, userBalance);
            }
            rewardList[i] = HarvestableReward({token: token, amount: reward});
        }
    }

    function _harvestableReward(
        address user,
        address token,
        uint256 globalRewardPerToken,
        uint256 userBalance
    ) internal view returns (uint256) {
        UserRewardSnapshot memory mUserRewardSnapshot = _userRewardSnapshot[user][token];
        return
            (userBalance * (globalRewardPerToken - mUserRewardSnapshot.rewardPerToken)) /
            _RATE_PRECISION +
            mUserRewardSnapshot.harvestableReward;
    }

    function plant(uint256 amount, address to) external nonReentrant whenNotPaused updateReward(to) {
        IERC20(underlyingToken).safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
        emit Plant(msg.sender, to, amount);
    }

    function unplant(uint256 amount, address to) external nonReentrant whenNotPaused updateReward(msg.sender) {
        _burn(msg.sender, amount);
        emit Unplant(msg.sender, to, amount);
        IERC20(underlyingToken).safeTransfer(to, amount);
    }

    function harvest(address user) external {
        harvest(user, _rewardTokens);
    }

    function harvest(address user, address[] memory tokenList) public nonReentrant whenNotPaused updateReward(user) {
        for (uint256 i = 0; i < tokenList.length; ++i) {
            address token = tokenList[i];
            uint256 reward = _userRewardSnapshot[user][token].harvestableReward;
            if (reward > 0) {
                _userRewardSnapshot[user][token].harvestableReward = 0;
                emit Harvest(user, token, reward);
                IERC20(token).safeTransfer(user, reward);
            }
        }
    }

    function supplyReward(address token, uint256 amount) external returns (uint256 supplyAmount) {
        GlobalRewardSnapshot memory mGlobalRewardSnapshot = _globalRewardSnapshot[token];
        if (mGlobalRewardSnapshot.treasury != msg.sender) {
            revert Errors.MangoError(Errors.ACCESS);
        }
        if (amount == 0) {
            return 0;
        }
        uint256 totalStakedAmount = totalSupply();
        if (totalStakedAmount == 0) {
            return 0;
        }
        uint256 rewardPerTokenIncrement = (amount * _RATE_PRECISION) / totalStakedAmount;
        supplyAmount = _divideCeil(rewardPerTokenIncrement * totalStakedAmount, _RATE_PRECISION);
        if (supplyAmount == 0) {
            return 0;
        }
        IERC20(token).safeTransferFrom(msg.sender, address(this), supplyAmount);

        mGlobalRewardSnapshot.rewardPerToken += rewardPerTokenIncrement;
        mGlobalRewardSnapshot.timestamp = uint64(block.timestamp);

        emit DistributeReward(msg.sender, token, supplyAmount, mGlobalRewardSnapshot.rewardPerToken, totalStakedAmount);
        _globalRewardSnapshot[token] = mGlobalRewardSnapshot;
    }

    function addRewardToken(address newRewardToken, address treasury) external onlyOwner {
        _addRewardToken(newRewardToken, treasury);
    }

    function _addRewardToken(address newRewardToken, address treasury) internal {
        if (_globalRewardSnapshot[newRewardToken].timestamp != 0) {
            revert Errors.MangoError(Errors.ACCESS);
        }
        if (ITreasury(treasury).rewardToken() != newRewardToken) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        _rewardTokens.push(newRewardToken);
        _globalRewardSnapshot[newRewardToken] = GlobalRewardSnapshot({
            rewardPerToken: 0,
            treasury: treasury,
            timestamp: uint64(block.timestamp)
        });
    }

    function withdrawLostERC20(address token, address to) external onlyOwner {
        if (token == underlyingToken || _globalRewardSnapshot[token].timestamp > 0) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    function _divideCeil(uint256 x, uint256 y) private pure returns (uint256) {
        return (x + y - 1) / y;
    }
}
