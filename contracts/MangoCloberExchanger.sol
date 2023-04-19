// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ICloberExchanger.sol";
import "./utils/ReentrancyGuard.sol";
import "./clober/CloberOrderBook.sol";
import "./clober/CloberOrderNFT.sol";

contract MangoCloberExchanger is ICloberExchanger, Initializable, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant _EMPTY_ORDER_ID = type(uint256).max;

    address public immutable override outputToken;
    CloberOrderBook private immutable _market;
    CloberOrderNFT private immutable _orderNFT;
    address public immutable override inputToken;
    bool private immutable _isBid;

    ITokenReceiver public override outputTokenReceiver;
    uint256 public override currentOrderId;

    constructor(address inputToken_, address outputToken_, address market_) {
        inputToken = inputToken_;
        outputToken = outputToken_;
        _market = CloberOrderBook(market_);
        _orderNFT = CloberOrderNFT(_market.orderToken());
        address quote = _market.quoteToken();
        address base = _market.baseToken();
        if (!(quote == inputToken_ && base == outputToken_) && !(quote == outputToken_ && base == inputToken_)) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        _isBid = quote == inputToken ? true : false;
    }

    function initialize(address outputTokenReceiver_) external initializer {
        _initReentrancyGuard();
        _transferOwnership(msg.sender);
        outputTokenReceiver = ITokenReceiver(outputTokenReceiver_);
        if (outputTokenReceiver.receivingToken() != outputToken) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        currentOrderId = _EMPTY_ORDER_ID;
        setApprovals();
    }

    function setApprovals() public {
        IERC20(outputToken).safeApprove(address(outputTokenReceiver), 0);
        IERC20(outputToken).safeApprove(address(outputTokenReceiver), type(uint256).max);
    }

    function receivingToken() external view returns (address) {
        return address(inputToken);
    }

    function market() external view returns (address) {
        return address(_market);
    }

    function transferableAmount() public view returns (uint256) {
        return IERC20(outputToken).balanceOf(address(this)) + _claimableAmount();
    }

    function hasNoOpenOrder() public view returns (bool) {
        return currentOrderId == _EMPTY_ORDER_ID;
    }

    function _claimableAmount() internal view returns (uint256 amount) {
        if (hasNoOpenOrder()) {
            return 0;
        }
        (, amount, , ) = _market.getClaimable(_orderNFT.decodeId(currentOrderId));
    }

    function receiveToken(uint256 amount) external nonReentrant {
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), amount);
        emit Receive(msg.sender, amount);
    }

    function limitOrder(uint16 priceIndex) external nonReentrant onlyOwner {
        if (!hasNoOpenOrder()) {
            _cancelOrder();
        }
        uint256 orderAmount = IERC20(inputToken).balanceOf(address(this));

        uint256 orderIndex = _market.limitOrder(
            address(this),
            priceIndex,
            _isBid ? _market.quoteToRaw(orderAmount, false) : 0,
            _isBid ? 0 : orderAmount,
            _isBid ? 1 : 0,
            new bytes(0)
        );
        if (orderIndex != type(uint256).max) {
            currentOrderId = _orderNFT.encodeId(
                OrderKey({isBid: _isBid, priceIndex: priceIndex, orderIndex: orderIndex})
            );
        } else {
            currentOrderId = _EMPTY_ORDER_ID;
        }
    }

    function cloberMarketSwapCallback(
        address inputToken_,
        address outputToken_,
        uint256 inputAmount,
        uint256,
        bytes calldata
    ) external payable {
        if (msg.sender != address(_market)) {
            revert Errors.MangoError(Errors.ACCESS);
        }
        if (!(inputToken_ == inputToken && outputToken_ == outputToken)) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        IERC20(inputToken).safeTransfer(msg.sender, inputAmount);
    }

    function _cancelOrder() internal {
        OrderKey[] memory orderKeys = new OrderKey[](1);
        orderKeys[0] = _orderNFT.decodeId(currentOrderId);
        _market.cancel(address(this), orderKeys);
        currentOrderId = _EMPTY_ORDER_ID;
    }

    function transferOutputToken() external nonReentrant {
        if (_claimableAmount() > 0) {
            OrderKey[] memory orderKeys = new OrderKey[](1);
            orderKeys[0] = _orderNFT.decodeId(currentOrderId);
            _market.claim(address(this), orderKeys);
        }
        uint256 amount = IERC20(outputToken).balanceOf(address(this));
        if (amount > 0) {
            outputTokenReceiver.receiveToken(amount);
        }
    }

    function setReceiver(ITokenReceiver receiver) external onlyOwner {
        IERC20(outputToken).safeApprove(address(outputTokenReceiver), 0);
        if (receiver.receivingToken() != outputToken) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        outputTokenReceiver = receiver;
        IERC20(outputToken).safeApprove(address(outputTokenReceiver), type(uint256).max);
    }

    function withdrawLostERC20(address token, address to) external onlyOwner {
        if (token == outputToken || token == inputToken) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount > 0) {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
