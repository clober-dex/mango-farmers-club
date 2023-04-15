// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "./Constants.sol";
import "../../contracts/clober/CloberRouter.sol";

library CloberOrderParamBuilder {
    function build(
        bool isBid,
        address user,
        uint16 priceIndex,
        uint256 amount
    ) internal view returns (CloberRouter.LimitOrderParams memory) {
        CloberRouter.LimitOrderParams memory params;
        params.market = Constants.MANGO_USDC_MARKET_ADDRESS;
        params.deadline = uint64(block.timestamp + 100);
        params.claimBounty = 0;
        params.user = user;
        params.rawAmount = isBid ? uint64(amount) : 0;
        params.priceIndex = priceIndex;
        params.postOnly = false;
        params.useNative = false;
        params.baseAmount = isBid ? 0 : amount;
        return params;
    }

    function build(
        bool isBid,
        uint16 priceIndex,
        uint256 amount
    ) internal view returns (CloberRouter.LimitOrderParams memory) {
        return build(isBid, msg.sender, priceIndex, amount);
    }

    function buildAsk(uint16 priceIndex, uint256 amount) internal view returns (CloberRouter.LimitOrderParams memory) {
        return build(false, msg.sender, priceIndex, amount);
    }

    function buildAsk(
        uint16 priceIndex,
        address user,
        uint256 amount
    ) internal view returns (CloberRouter.LimitOrderParams memory) {
        return build(false, user, priceIndex, amount);
    }

    function buildBid(uint16 priceIndex, uint256 amount) internal view returns (CloberRouter.LimitOrderParams memory) {
        return build(true, msg.sender, priceIndex, amount);
    }

    function buildBid(
        uint16 priceIndex,
        address user,
        uint256 amount
    ) internal view returns (CloberRouter.LimitOrderParams memory) {
        return build(true, user, priceIndex, amount);
    }
}
