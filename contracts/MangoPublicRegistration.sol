// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./interfaces/IMangoPublicRegistration.sol";
import "./interfaces/ITokenReceiver.sol";
import "./utils/ReentrancyGuard.sol";
import "./Errors.sol";
import "./utils/Pausable.sol";

contract MangoPublicRegistration is IMangoPublicRegistration, ReentrancyGuard, Ownable, Pausable, Initializable {
    using SafeERC20 for IERC20;

    uint256 private constant _MANGO_DECIMALS = 18;
    uint256 private constant _USDC_DECIMALS = 6;
    uint256 private constant _MANGO_PRECISION = 10 ** _MANGO_DECIMALS;
    uint256 private constant _USDC_PRECISION = 10 ** _USDC_DECIMALS;

    address private constant _BURN_ADDRESS = address(0xdead);

    uint256 private constant _MANGO_ALLOCATION_AMOUNT = 4_500_000_000 * _MANGO_PRECISION; // 4.5 billion MANGO tokens
    uint256 private constant _USDC_HARDCAP = 400_000 * _USDC_PRECISION; // 400,000 USDC
    uint256 private constant _LIMIT_PER_WALLET = 1000 * _USDC_PRECISION; // 1000 USDC

    IERC20 private immutable _mangoToken;
    IERC20 private immutable _usdcToken;

    uint256 public immutable override startTime;
    uint256 public immutable override endTime; // startTime + 7 days

    mapping(address => uint256) public override depositAmount;
    mapping(address => bool) public override claimed;

    uint256 public override totalDeposit;

    constructor(uint256 startTime_, address mangoToken_, address usdcToken_) {
        if (startTime_ <= block.timestamp) {
            revert Errors.MangoError(Errors.INVALID_TIME);
        }

        startTime = startTime_;
        endTime = startTime_ + 7 days;
        _mangoToken = IERC20(mangoToken_);
        _usdcToken = IERC20(usdcToken_);
    }

    function initialize() external initializer {
        _initReentrancyGuard();
        _transferOwnership(msg.sender);
    }

    modifier inTime() {
        if (block.timestamp < startTime || endTime <= block.timestamp) {
            revert Errors.MangoError(Errors.INVALID_TIME);
        }
        _;
    }

    function _divideCeil(uint256 x, uint256 y) private pure returns (uint256) {
        return (x + y - 1) / y;
    }

    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x < y ? x : y;
    }

    // deposit USDC to contract
    function deposit(uint256 amount) external inTime whenNotPaused {
        if (depositAmount[msg.sender] + amount > _LIMIT_PER_WALLET) {
            revert Errors.MangoError(Errors.EXCEEDED_BALANCE);
        }

        _usdcToken.safeTransferFrom(msg.sender, address(this), amount);
        depositAmount[msg.sender] += amount;
        totalDeposit += amount;

        emit Deposit(msg.sender, amount);
    }

    // claim MANGO tokens, plus USDC refund if hardcap is exceeded
    function claim(address receiver) external nonReentrant whenNotPaused {
        if (block.timestamp < endTime) {
            revert Errors.MangoError(Errors.INVALID_TIME);
        }
        if (depositAmount[receiver] == 0) {
            revert Errors.MangoError(Errors.INSUFFICIENT_BALANCE);
        }
        if (claimed[receiver]) {
            revert Errors.MangoError(Errors.ACCESS);
        }

        uint256 depositAmountOfReceiver = depositAmount[receiver];

        if (totalDeposit > _USDC_HARDCAP) {
            uint256 mangoAmount = (_MANGO_ALLOCATION_AMOUNT * depositAmountOfReceiver) / totalDeposit;
            uint256 usdcRefundAmount = depositAmountOfReceiver -
                _divideCeil(mangoAmount * _USDC_HARDCAP, _MANGO_ALLOCATION_AMOUNT);
            _mangoToken.safeTransfer(receiver, mangoAmount);
            _usdcToken.safeTransfer(receiver, usdcRefundAmount);
            emit Claim(msg.sender, receiver, mangoAmount, usdcRefundAmount);
        } else {
            uint256 mangoAmount = (depositAmountOfReceiver * _MANGO_ALLOCATION_AMOUNT) / _USDC_HARDCAP;
            _mangoToken.safeTransfer(receiver, mangoAmount);
            emit Claim(msg.sender, receiver, mangoAmount, 0);
        }

        claimed[receiver] = true;
    }

    function transferUSDCToReceiver(address usdcReceiver) external onlyOwner {
        if (block.timestamp < endTime) {
            revert Errors.MangoError(Errors.INVALID_TIME);
        }
        uint256 transferAmount = _min(totalDeposit, _USDC_HARDCAP);
        _usdcToken.approve(usdcReceiver, transferAmount);
        ITokenReceiver(usdcReceiver).receiveToken(transferAmount);
    }

    function burnUnsoldMango() external onlyOwner {
        if (block.timestamp < endTime) {
            revert Errors.MangoError(Errors.INVALID_TIME);
        }
        if (totalDeposit < _USDC_HARDCAP) {
            uint256 unsoldMangoAmount = _MANGO_ALLOCATION_AMOUNT -
                _divideCeil(totalDeposit * _MANGO_ALLOCATION_AMOUNT, _USDC_HARDCAP);
            _mangoToken.safeTransfer(_BURN_ADDRESS, unsoldMangoAmount);
        }
    }
}
