// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./clober/CloberOrderBook.sol";
import "./clober/CloberOrderKey.sol";
import "./clober/CloberOrderNFT.sol";
import "./interfaces/IBondPool.sol";
import "./interfaces/ITreasury.sol";
import "./Errors.sol";
import "./utils/ReentrancyGuard.sol";
import "./clober/CloberMarketSwapCallbackReceiver.sol";
import "./utils/Pausable.sol";

contract MangoBondPool is
    IBondPool,
    Initializable,
    Ownable,
    Pausable,
    ReentrancyGuard,
    CloberMarketSwapCallbackReceiver
{
    using SafeERC20 for IERC20;
    uint256 private constant _FEE_PRECISION = 10 ** 6;

    ITreasury private immutable _treasury;
    address public immutable override burnAddress;
    address public immutable override underlyingToken;
    address public immutable override quoteToken;
    uint256 public immutable override cancelFee;
    uint256 public immutable override releaseRate;
    uint256 public immutable override maxReleaseAmount;
    uint16 public immutable override initialBondPriceIndex;
    CloberOrderBook private immutable _market;
    CloberOrderNFT private immutable _orderNFT;

    uint8 public override minBonus;
    uint8 public override maxBonus;
    uint64 public override lastReleasedAt;
    uint16 public override sampleSize;
    uint256 private _lastRecordedReleasedAmount;
    uint256 private _soldAmount;

    mapping(uint256 => Bond) private _bonds;

    constructor(
        address treasury_,
        address burnAddress_,
        address underlyingToken_,
        uint256 cancelFee_,
        address market_,
        uint256 releaseRate_,
        uint256 maxReleaseAmount_,
        uint16 initialBondPriceIndex_
    ) {
        _treasury = ITreasury(treasury_);
        burnAddress = burnAddress_;
        _market = CloberOrderBook(market_);
        _orderNFT = CloberOrderNFT(_market.orderToken());
        if (_market.baseToken() != underlyingToken_) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        // change needed if market policy change to allow non-zero makerFee
        if (_market.makerFee() != 0) {
            revert Errors.MangoError(Errors.INVALID_FEE);
        }
        underlyingToken = underlyingToken_;
        cancelFee = cancelFee_;
        quoteToken = _market.quoteToken();
        releaseRate = releaseRate_;
        maxReleaseAmount = maxReleaseAmount_;
        initialBondPriceIndex = initialBondPriceIndex_;
    }

    function initialize(uint8 minBonus_, uint8 maxBonus_, uint64 startAt_, uint16 sampleSize_) external initializer {
        _initReentrancyGuard();
        _transferOwnership(msg.sender);
        _changeAvailableBonusRange(minBonus_, maxBonus_);
        lastReleasedAt = startAt_;
        sampleSize = sampleSize_;
        setApprovals();
    }

    modifier checkBonusRange(uint8 bonus) {
        if (bonus > maxBonus || bonus < minBonus) {
            revert Errors.MangoError(Errors.INVALID_BONUS);
        }
        _;
    }

    function setApprovals() public {
        IERC20(quoteToken).safeApprove(address(_treasury), type(uint256).max);
    }

    function market() external view returns (address) {
        return address(_market);
    }

    function treasury() external view returns (address) {
        return address(_treasury);
    }

    function ownerOf(uint256 orderId) external view returns (address) {
        return _bonds[orderId].owner;
    }

    function ownersOf(uint256[] calldata orderIds) external view returns (address[] memory) {
        address[] memory owners = new address[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; i++) {
            owners[i] = _bonds[orderIds[i]].owner;
        }
        return owners;
    }

    function claimable(uint256 orderId) external view returns (uint256 claimableAmount) {
        OrderKey memory orderKey = _decodeOrderId(orderId);
        Bond memory bond = _bonds[orderId];
        if (!bond.isValid) {
            return 0;
        }
        (, claimableAmount, , ) = _market.getClaimable(orderKey);
        claimableAmount += _unaccountedClaimedAmount(bond, orderKey);
    }

    function unaccountedClaimedAmount(uint256 orderId) external view returns (uint256) {
        return _unaccountedClaimedAmount(_bonds[orderId], _decodeOrderId(orderId));
    }

    function _unaccountedClaimedAmount(
        Bond memory bond,
        OrderKey memory orderKey
    ) internal view returns (uint256 amount) {
        uint64 remoteOrderRawAmount = _market.getOrder(orderKey).amount;
        uint64 unaccountedClaimedRawAmount = bond.purchasedRawAmount - remoteOrderRawAmount - bond.claimedRawAmount;
        if (unaccountedClaimedRawAmount == 0) {
            return 0;
        }
        amount = _market.rawToQuote(unaccountedClaimedRawAmount);
    }

    function releasedAmount() public view returns (uint256 newReleasedAmount) {
        // @dev Assume that `lastReleasedAt` is not 0. We initialize this value in `initialize()`.
        uint256 timeDiff = block.timestamp - lastReleasedAt;
        newReleasedAmount = _lastRecordedReleasedAmount + releaseRate * timeDiff;
        if (newReleasedAmount > maxReleaseAmount) {
            newReleasedAmount = maxReleaseAmount;
        }
    }

    function availableAmount() public view returns (uint256) {
        return releasedAmount() - _soldAmount;
    }

    function _release() internal {
        if (block.timestamp > lastReleasedAt) {
            _lastRecordedReleasedAmount = releasedAmount();
            lastReleasedAt = uint64(block.timestamp);
        }
    }

    function bondInfo(uint256 orderId) external view returns (BondInfo memory) {
        Bond memory bond = _bonds[orderId];
        uint16 priceIndex = _decodeOrderId(orderId).priceIndex;
        return
            BondInfo({
                orderId: orderId,
                owner: bond.owner,
                bonus: bond.bonus,
                isValid: bond.isValid,
                spentAmount: _market.rawToQuote(bond.spentRawAmount),
                bondedAmount: _market.rawToBase(bond.purchasedRawAmount, priceIndex, false),
                claimedAmount: _market.rawToQuote(bond.claimedRawAmount),
                canceledAmount: _market.rawToBase(bond.canceledRawAmount, priceIndex, false)
            });
    }

    function getBasisPriceIndex() public view returns (uint16 priceIndex) {
        uint16 index = _market.blockTradeLogIndex();
        uint16 size = sampleSize;
        priceIndex = 0;
        uint16 gap = 2;
        for (uint256 i = 0; i < size; ++i) {
            CloberOrderBook.BlockTradeLog memory log = _market.blockTradeLogs(index);
            if (i == 0 && log.blockTime == block.timestamp) {
                // skip log of the same block
                unchecked {
                    index -= 1;
                }
                log = _market.blockTradeLogs(index);
            }
            // check empty block log
            if (log.blockTime == 0) {
                if (priceIndex < initialBondPriceIndex) {
                    return initialBondPriceIndex;
                }
                break;
            }
            if (log.high > priceIndex) {
                priceIndex = log.high;
            }
            unchecked {
                index -= gap;
                gap *= 2;
            }
        }
        if (priceIndex == 0) {
            return initialBondPriceIndex;
        }
    }

    function getBasisPrice() external view returns (uint256 price) {
        return _market.indexToPrice(getBasisPriceIndex());
    }

    function expectedBondAmount(
        uint256 spentAmount,
        uint8 bonus
    ) external view checkBonusRange(bonus) returns (uint256 amount) {
        uint64 spentRawAmount = _market.quoteToRaw(spentAmount, false);
        (uint16 priceIndex, uint256 orderAmount) = _calculateOrder(spentRawAmount, bonus);
        amount = _market.rawToBase(_market.baseToRaw(orderAmount, priceIndex, false), priceIndex, false);
    }

    function _calculateOrder(
        uint64 spentRawAmount,
        uint8 bonus
    ) internal view returns (uint16 priceIndex, uint256 amount) {
        uint16 basisPriceIndex = getBasisPriceIndex();
        uint256 underlyingAmount = _market.rawToBase(spentRawAmount, basisPriceIndex, false);
        priceIndex = basisPriceIndex + bonus;
        uint64 orderRawAmount = _market.baseToRaw(underlyingAmount, priceIndex, false);
        amount = _market.rawToBase(orderRawAmount, basisPriceIndex, false);
    }

    function purchaseBond(
        uint256 spentAmount,
        uint8 bonus,
        address to,
        uint16 limitPriceIndex
    ) external nonReentrant whenNotPaused checkBonusRange(bonus) returns (uint256 orderId) {
        _release();
        uint64 spentRawAmount = _market.quoteToRaw(spentAmount, false);
        spentAmount = _market.rawToQuote(spentRawAmount);
        IERC20(quoteToken).safeTransferFrom(msg.sender, address(this), spentAmount);
        (uint16 priceIndex, uint256 orderAmount) = _calculateOrder(spentRawAmount, bonus);
        if (availableAmount() < orderAmount) {
            revert Errors.MangoError(Errors.INSUFFICIENT_BALANCE);
        }
        if (priceIndex > limitPriceIndex) {
            revert Errors.MangoError(Errors.SLIPPAGE);
        }
        uint64 orderedRawAmount;
        {
            // post only
            uint256 orderIndex = _market.limitOrder(address(this), priceIndex, 0, orderAmount, 2, new bytes(0));
            if (orderIndex == type(uint256).max) {
                // It represents order is not created b/c the orderAmount is too small.
                revert Errors.MangoError(Errors.AMOUNT_TOO_SMALL);
            }
            OrderKey memory orderKey = OrderKey({isBid: false, priceIndex: priceIndex, orderIndex: orderIndex});
            orderId = _orderNFT.encodeId(orderKey);
            orderedRawAmount = _market.getOrder(orderKey).amount;
        }
        _bonds[orderId] = Bond({
            spentRawAmount: spentRawAmount,
            purchasedRawAmount: orderedRawAmount,
            claimedRawAmount: 0,
            canceledRawAmount: 0,
            owner: to,
            bonus: bonus,
            isValid: true
        });
        uint256 underlyingAmount = _market.rawToBase(orderedRawAmount, priceIndex, false);
        if (underlyingAmount == 0) {
            // Check if the underlyingAmount is 0 due to the rounding calculation.
            revert Errors.MangoError(Errors.AMOUNT_TOO_SMALL);
        }
        emit PurchaseBond(msg.sender, to, orderId, spentAmount, bonus, underlyingAmount);

        _treasury.receiveToken(spentAmount);
    }

    function cloberMarketSwapCallback(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256,
        bytes calldata
    ) external payable {
        if (msg.sender != address(_market)) {
            revert Errors.MangoError(Errors.ACCESS);
        }
        if (!(inputToken == underlyingToken && outputToken == quoteToken)) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        IERC20(inputToken).safeTransfer(msg.sender, inputAmount);
        _soldAmount += inputAmount;
    }

    function claim(uint256[] calldata orderIds) public nonReentrant whenNotPaused {
        for (uint256 i = 0; i < orderIds.length; ++i) {
            uint256 claimedAmount;
            uint256 orderId = orderIds[i];
            Bond memory bond = _bonds[orderId];
            if (!bond.isValid) {
                continue;
            }
            OrderKey memory orderKey = _decodeOrderId(orderId);
            claimedAmount += _unaccountedClaimedAmount(bond, orderKey);
            uint256 beforeQuoteAmount = IERC20(quoteToken).balanceOf(address(this));
            _market.claim(msg.sender, _toSingletonArray(orderKey));
            claimedAmount += IERC20(quoteToken).balanceOf(address(this)) - beforeQuoteAmount;
            if (claimedAmount > 0) {
                IERC20(quoteToken).safeTransfer(bond.owner, claimedAmount);

                uint64 remoteOrderRawAmount = _market.getOrder(orderKey).amount;
                bond.claimedRawAmount = bond.purchasedRawAmount - remoteOrderRawAmount;
                if (bond.purchasedRawAmount == bond.claimedRawAmount) {
                    bond.isValid = false;
                }
                _bonds[orderId] = bond;
            }
        }
    }

    function breakBonds(uint256[] calldata orderIds) external nonReentrant whenNotPaused {
        OrderKey[] memory orderKeys = new OrderKey[](orderIds.length);
        for (uint256 i = 0; i < orderIds.length; ++i) {
            uint256 orderId = orderIds[i];
            Bond memory bond = _bonds[orderId];
            if (bond.owner != msg.sender) {
                revert Errors.MangoError(Errors.ACCESS);
            }
            OrderKey memory orderKey = _decodeOrderId(orderId);
            orderKeys[i] = orderKey;
            if (!bond.isValid) {
                continue;
            }
            uint64 remoteOrderRawAmount = _market.getOrder(orderKey).amount;
            (uint64 claimableRawAmount, , , ) = _market.getClaimable(orderKey);
            bond.canceledRawAmount = remoteOrderRawAmount - claimableRawAmount;
            bond.claimedRawAmount = bond.purchasedRawAmount - bond.canceledRawAmount;
            bond.isValid = false;
            _bonds[orderId] = bond;
        }
        uint256 beforeQuoteAmount = IERC20(quoteToken).balanceOf(address(this));
        uint256 beforeUnderlyingAmount = IERC20(underlyingToken).balanceOf(address(this));
        _market.cancel(address(this), orderKeys);
        uint256 claimedQuoteAmount = IERC20(quoteToken).balanceOf(address(this)) - beforeQuoteAmount;
        uint256 canceledUnderlyingAmount = IERC20(underlyingToken).balanceOf(address(this)) - beforeUnderlyingAmount;

        uint256 cancelFeeAmount = _ceil(canceledUnderlyingAmount * cancelFee, _FEE_PRECISION);
        IERC20(underlyingToken).safeTransfer(burnAddress, cancelFeeAmount);
        IERC20(underlyingToken).safeTransfer(msg.sender, canceledUnderlyingAmount - cancelFeeAmount);
        IERC20(quoteToken).safeTransfer(msg.sender, claimedQuoteAmount);
    }

    function withdrawLostERC20(address token, address to) external onlyOwner {
        if (token == underlyingToken || token == quoteToken) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    function changeAvailableBonusRange(uint8 min, uint8 max) external onlyOwner {
        _changeAvailableBonusRange(min, max);
    }

    function changePriceSampleSize(uint16 newSampleSize) external onlyOwner {
        sampleSize = newSampleSize;
    }

    function _changeAvailableBonusRange(uint8 min, uint8 max) internal {
        if (min > max) {
            revert Errors.MangoError(Errors.INVALID_BONUS);
        }
        minBonus = min;
        maxBonus = max;
    }

    function _decodeOrderId(uint256 orderId) internal view returns (OrderKey memory) {
        return _orderNFT.decodeId(orderId);
    }

    function _ceil(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    function _toSingletonArray(OrderKey memory orderKey) internal pure returns (OrderKey[] memory arr) {
        arr = new OrderKey[](1);
        arr[0] = orderKey;
    }
}
