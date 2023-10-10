// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBondPool {
    event PurchaseBond(
        address indexed payer,
        address indexed to,
        uint256 indexed orderId,
        uint256 spentAmount,
        uint8 bonus,
        uint256 bondedAmount
    );

    struct Bond {
        uint64 spentRawAmount;
        uint64 purchasedRawAmount;
        uint64 claimedRawAmount;
        uint64 canceledRawAmount;
        address owner;
        uint8 bonus;
        bool isValid; // Only true when the order is opened
    }

    struct BondInfo {
        uint256 orderId;
        address owner;
        uint8 bonus;
        bool isValid;
        uint256 spentAmount;
        uint256 bondedAmount;
        uint256 claimedAmount;
        uint256 canceledAmount; // fee excluded
    }

    struct BondOwner {
        address owner;
        uint256 orderId;
    }

    function burnAddress() external view returns (address);

    function underlyingToken() external view returns (address);

    function quoteToken() external view returns (address);

    function cancelFee() external view returns (uint256);

    function market() external view returns (address);

    function treasury() external view returns (address);

    function minBonus() external view returns (uint8);

    function maxBonus() external view returns (uint8);

    function releaseRate() external view returns (uint256);

    function maxReleaseAmount() external view returns (uint256);

    function initialBondPriceIndex() external view returns (uint16);

    function lastReleasedAt() external view returns (uint64);

    function sampleSize() external view returns (uint16);

    function lastRecordedReleasedAmount() external view returns (uint256);

    function soldAmount() external view returns (uint256);

    function ownerOf(uint256 orderId) external view returns (address);

    function ownersOf(uint256[] calldata orderIds) external view returns (BondOwner[] memory);

    function claimable(uint256 orderId) external view returns (uint256);

    function unaccountedClaimedAmount(uint256 orderId) external view returns (uint256);

    function releasedAmount() external view returns (uint256);

    function availableAmount() external view returns (uint256);

    function bondInfo(uint256 orderId) external view returns (BondInfo memory);

    function bondInfos(uint256[] calldata orderIds) external view returns (BondInfo[] memory);

    function getBasisPriceIndex() external view returns (uint16 priceIndex);

    function getBasisPrice() external view returns (uint256 price);

    function expectedBondAmount(uint256 spentAmount, uint8 bonus) external view returns (uint256);

    function purchaseBond(
        uint256 spentAmount,
        uint8 bonus,
        address to,
        uint16 limitPriceIndex
    ) external returns (uint256 orderId);

    function claim(uint256[] calldata orderIds) external;

    function breakBonds(uint256[] calldata orderIds) external;

    function refund(uint256[] calldata orderIds) external;

    function withdrawLostERC20(address token, address to) external;

    function changeAvailableBonusRange(uint8 min, uint8 max) external;

    function changePriceSampleSize(uint16 sampleSize) external;

    function withdrawExceededUnderlyingToken(address receiver) external;
}
