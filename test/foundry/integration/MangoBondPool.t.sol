// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../contracts/clober/CloberOrderNFT.sol";
import "../../../contracts/clober/CloberRouter.sol";
import "../../../contracts/clober/CloberOrderBook.sol";
import "../../../contracts/MangoTreasury.sol";
import "../../../contracts/MangoStakedToken.sol";
import "../../../contracts/MangoBondPool.sol";
import "../../mocks/MockUSDC.sol";
import "../CloberForkTestSetUp.sol";
import "../Constants.sol";

contract MangoBondPoolIntegrationTest is Test {
    address constant MANGO_INITIAL_RECEIVER = 0x7D97304bcFC75E10def10db3A71d7FF76ce11bD0;
    address constant PROXY_ADMIN = address(0x1231241);
    uint256 constant CANCEL_FEE = 200000; // 20%
    uint256 constant MAX_RELEASE_AMOUNT = 500_000_000 * (10 ** 18);
    uint256 constant RELEASE_RATE_PER_SECOND = 11574074074074073088; // MAX_RELEASE_AMOUNT // (60 * 60 * 24 * 500)
    address constant BURN_ADDRESS = address(0xdead);
    uint16 constant INITIAL_BOND_PRICE_INDEX = 219; // log_1.01(0.000089 / 0.00001)

    CloberRouter router;
    CloberOrderBook market;
    CloberOrderNFT orderNFT;

    MangoTreasury treasury;
    MangoStakedToken stakedToken;
    MangoBondPool bondPool;
    ERC20 mangoToken;
    ERC20 usdcToken;
    uint256 startsAt;

    function setUp() public {
        CloberForkTestSetUp forkTestSetUp = new CloberForkTestSetUp();
        (router, market) = forkTestSetUp.run();
        orderNFT = CloberOrderNFT(market.orderToken());
        mangoToken = ERC20(Constants.MANGO_ADDRESS);
        usdcToken = ERC20(Constants.USDC_ADDRESS);

        startsAt = block.timestamp + 100;
        address stakedTokenLogic = address(new MangoStakedToken(address(mangoToken)));
        stakedToken = MangoStakedToken(
            address(new TransparentUpgradeableProxy(stakedTokenLogic, PROXY_ADMIN, new bytes(0)))
        );
        address treasuryLogic = address(new MangoTreasury(address(stakedToken), address(usdcToken), address(0)));
        treasury = MangoTreasury(
            address(
                new TransparentUpgradeableProxy(
                    treasuryLogic,
                    PROXY_ADMIN,
                    abi.encodeWithSelector(MangoTreasury.initialize.selector, startsAt)
                )
            )
        );
        stakedToken.initialize(_toArray(address(usdcToken)), _toArray(address(treasury)));

        usdcToken.approve(address(treasury), type(uint256).max);
        mangoToken.approve(address(stakedToken), type(uint256).max);

        address bondPoolLogic = address(
            new MangoBondPool(
                address(treasury),
                BURN_ADDRESS,
                Constants.MANGO_ADDRESS,
                CANCEL_FEE,
                Constants.MANGO_USDC_MARKET_ADDRESS,
                RELEASE_RATE_PER_SECOND,
                MAX_RELEASE_AMOUNT,
                INITIAL_BOND_PRICE_INDEX
            )
        );
        bondPool = MangoBondPool(
            address(
                new TransparentUpgradeableProxy(
                    bondPoolLogic,
                    PROXY_ADMIN,
                    abi.encodeWithSelector(MangoBondPool.initialize.selector, 5, 15, uint32(block.timestamp), 10)
                )
            )
        );
        usdcToken.approve(address(bondPool), type(uint256).max);

        // set user USDC balance
        usdcToken.transfer(Constants.USER_A_ADDRESS, 1000 * (10 ** 6));
        vm.startPrank(Constants.USER_A_ADDRESS);
        usdcToken.approve(address(bondPool), type(uint256).max);
        usdcToken.approve(address(router), type(uint256).max);
        vm.stopPrank();

        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
    }

    function _createLimitOrder(bool isBid, uint16 priceIndex, uint64 rawAmount) private returns (uint256) {
        if (isBid) {
            return
                router.limitBid(
                    CloberRouter.LimitOrderParams({
                        market: Constants.MANGO_USDC_MARKET_ADDRESS,
                        deadline: uint64(block.timestamp + 100),
                        claimBounty: 0,
                        user: Constants.USER_A_ADDRESS,
                        priceIndex: priceIndex,
                        rawAmount: rawAmount,
                        postOnly: false,
                        useNative: false,
                        baseAmount: 0
                    })
                );
        } else {
            return
                router.limitAsk(
                    CloberRouter.LimitOrderParams({
                        market: Constants.MANGO_USDC_MARKET_ADDRESS,
                        deadline: uint64(block.timestamp + 100),
                        claimBounty: 0,
                        user: Constants.USER_A_ADDRESS,
                        priceIndex: priceIndex,
                        rawAmount: 0,
                        postOnly: false,
                        useNative: false,
                        baseAmount: market.rawToBase(rawAmount, priceIndex, true)
                    })
                );
        }
    }

    function _toArray(address a) private pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function _toArray(OrderKey memory a) private pure returns (OrderKey[] memory arr) {
        arr = new OrderKey[](1);
        arr[0] = a;
    }

    function _checkPurchaseBond(
        uint256 amount,
        uint8 bonus,
        address user,
        uint256 expectedOrderIndex,
        uint256 expectedSoldAmount
    ) private {
        uint256 orderId = bondPool.purchaseBond(amount, bonus, user, type(uint16).max);
        uint256 expectedOrderId = orderNFT.encodeId(
            OrderKey({isBid: false, priceIndex: bondPool.getBasisPriceIndex() + bonus, orderIndex: expectedOrderIndex})
        );

        // check Bond info
        IBondPool.BondInfo memory bond = bondPool.bondInfo(orderId);
        assertEq(bond.orderId, expectedOrderId, "ERROR_BOND_ORDER_ID");
        assertEq(bond.owner, user, "ERROR_BOND_OWNER");
        assertEq(bond.bonus, bonus, "ERROR_BOND_BONUS");
        assertEq(bond.isValid, true, "ERROR_BOND_IS_VALID");
        assertEq(bond.spentAmount, amount, "ERROR_BOND_SPENT_AMOUNT");
        assertEq(bond.bondedAmount, expectedSoldAmount, "ERROR_BOND_BONDED_AMOUNT");
        assertEq(bond.claimedAmount, 0, "ERROR_BOND_CLAIMED_AMOUNT");
        assertEq(bond.canceledAmount, 0, "ERROR_BOND_CANCELED_AMOUNT");
        assertEq(bondPool.ownerOf(orderId), user, "ERROR_BOND_OWNER_OF");
        assertEq(orderNFT.ownerOf(orderId), address(bondPool), "ERROR_ORDER_NFT_OWNER_OF");
    }

    function _checkClaim(address user, OrderKey memory orderKey, uint256 expectedClaimableRawAmount) private {
        uint256 orderId = orderNFT.encodeId(orderKey);
        IBondPool.BondInfo memory bond = bondPool.bondInfo(orderId);
        assertEq(bond.isValid, true, "ERROR_BOND_IS_VALID");
        assertEq(bond.orderId, orderId, "ERROR_BOND_ORDER_ID");
        (uint256 claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, expectedClaimableRawAmount, "ERROR_CLAIMABLE_RAW_AMOUNT");
        assertEq(bond.claimedAmount, 0, "ERROR_BEFORE_BOND_CLAIMED_AMOUNT");

        uint256 beforeUsdcBalance = usdcToken.balanceOf(user);
        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        vm.prank(user);
        bondPool.claim(orderIds);
        bond = bondPool.bondInfo(orderId);
        (claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, 0, "ERROR_CLAIMABLE_AMOUNT_FINAL");
        assertEq(bond.claimedAmount, expectedClaimableRawAmount, "ERROR_AFTER_BOND_CLAIMED_AMOUNT");

        if (expectedClaimableRawAmount > 0) {
            assertGt(usdcToken.balanceOf(user) - beforeUsdcBalance, 0);
        } else {
            assertEq(usdcToken.balanceOf(user) - beforeUsdcBalance, 0);
        }
    }

    function _checkBreakBond(
        address user,
        OrderKey memory orderKey,
        uint256 expectedUsdcBalance,
        uint256 expectedMangoBalance
    ) private {
        uint256 orderId = orderNFT.encodeId(orderKey);
        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        IBondPool.BondInfo memory bond = bondPool.bondInfo(orderId);
        if (!bond.isValid) {
            uint256 beforeUsdcBalance = usdcToken.balanceOf(user);
            vm.prank(user);
            bondPool.breakBonds(orderIds);
            assertEq(usdcToken.balanceOf(user) - beforeUsdcBalance, 0);
            return;
        }
        uint256 usdcBalanceBefore = usdcToken.balanceOf(user);
        uint256 mangoBalanceBefore = mangoToken.balanceOf(user);
        vm.prank(user);
        bondPool.breakBonds(orderIds);
        assertEq(usdcToken.balanceOf(user) - usdcBalanceBefore, expectedUsdcBalance, "ERROR_USDC_BALANCE");
        assertEq(mangoToken.balanceOf(user) - mangoBalanceBefore, expectedMangoBalance, "ERROR_MANGO_BALANCE");
    }

    function _ceil(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    function testBondScenario1() public {
        vm.warp(block.timestamp + 5000);
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
        assertEq(bondPool.availableAmount(), RELEASE_RATE_PER_SECOND * 5000);

        // A buy bond
        _checkPurchaseBond({
            amount: 10 ** 6,
            bonus: 5,
            user: Constants.USER_A_ADDRESS,
            expectedOrderIndex: 0,
            expectedSoldAmount: 11891207599903039367405
        });
        // B buy bond
        _checkPurchaseBond({
            amount: 10 ** 6,
            bonus: 6,
            user: Constants.USER_B_ADDRESS,
            expectedOrderIndex: 0,
            expectedSoldAmount: 12010110059918380040802
        });
        // C buy bond
        _checkPurchaseBond({
            amount: 10 ** 6,
            bonus: 7,
            user: Constants.USER_C_ADDRESS,
            expectedOrderIndex: 0,
            expectedSoldAmount: 12130209446735589972036
        });

        // bond A all taken, B partially taken.
        OrderKey memory OrderKeyForUserA = OrderKey({
            isBid: false,
            priceIndex: bondPool.getBasisPriceIndex() + 5,
            orderIndex: 0
        });
        OrderKey memory OrderKeyForUserB = OrderKey({
            isBid: false,
            priceIndex: bondPool.getBasisPriceIndex() + 6,
            orderIndex: 0
        });
        OrderKey memory OrderKeyForUserC = OrderKey({
            isBid: false,
            priceIndex: bondPool.getBasisPriceIndex() + 7,
            orderIndex: 0
        });
        uint64 rawAmountToTake = market.getOrder(OrderKeyForUserA).amount +
            market.getOrder(OrderKeyForUserB).amount /
            2;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: rawAmountToTake});

        uint256 snapshotId = vm.snapshot();
        // check all claim
        _checkClaim(Constants.USER_A_ADDRESS, OrderKeyForUserA, market.getOrder(OrderKeyForUserA).amount);
        _checkClaim(Constants.USER_B_ADDRESS, OrderKeyForUserB, market.getOrder(OrderKeyForUserB).amount / 2);
        _checkClaim(Constants.USER_C_ADDRESS, OrderKeyForUserC, 0);
        // check all cancel
        _checkBreakBond({
            user: Constants.USER_A_ADDRESS,
            orderKey: OrderKeyForUserA,
            expectedUsdcBalance: 0,
            expectedMangoBalance: 0
        });
        uint256 expectedMangoBalance = 6005055029959190020401;
        _checkBreakBond({
            user: Constants.USER_B_ADDRESS,
            orderKey: OrderKeyForUserB,
            expectedUsdcBalance: 0,
            expectedMangoBalance: expectedMangoBalance - _ceil(2 * expectedMangoBalance, 10)
        });
        expectedMangoBalance = 12130209446735589972036;
        _checkBreakBond({
            user: Constants.USER_C_ADDRESS,
            orderKey: OrderKeyForUserC,
            expectedUsdcBalance: 0,
            expectedMangoBalance: expectedMangoBalance - _ceil(2 * expectedMangoBalance, 10)
        });

        // check A,B didn't claim but cancel
        vm.revertTo(snapshotId);
        _checkBreakBond({
            user: Constants.USER_A_ADDRESS,
            orderKey: OrderKeyForUserA,
            expectedUsdcBalance: market.getOrder(OrderKeyForUserA).amount,
            expectedMangoBalance: 0
        });
        expectedMangoBalance = 6005055029959190020401;
        _checkBreakBond({
            user: Constants.USER_B_ADDRESS,
            orderKey: OrderKeyForUserB,
            expectedUsdcBalance: market.getOrder(OrderKeyForUserB).amount / 2,
            expectedMangoBalance: expectedMangoBalance - _ceil(2 * expectedMangoBalance, 10)
        });
    }

    function testBondScenario2() public {
        vm.warp(block.timestamp + 5000);
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
        assertEq(bondPool.availableAmount(), RELEASE_RATE_PER_SECOND * 5000);
        // A buy bond
        _checkPurchaseBond({
            amount: 10 ** 6,
            bonus: 5,
            user: Constants.USER_A_ADDRESS,
            expectedOrderIndex: 0,
            expectedSoldAmount: 11891207599903039367405
        });
        // B buy bond at the same price
        _checkPurchaseBond({
            amount: 10 ** 6,
            bonus: 5,
            user: Constants.USER_B_ADDRESS,
            expectedOrderIndex: 1,
            expectedSoldAmount: 11891207599903039367405
        });

        // only A's order has been taken.
        OrderKey memory OrderKeyForUserA = OrderKey({
            isBid: false,
            priceIndex: bondPool.getBasisPriceIndex() + 5,
            orderIndex: 0
        });
        OrderKey memory OrderKeyForUserB = OrderKey({
            isBid: false,
            priceIndex: bondPool.getBasisPriceIndex() + 5,
            orderIndex: 1
        });
        uint64 rawAmountToTake = market.getOrder(OrderKeyForUserA).amount;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: rawAmountToTake});

        // check only A can claim
        _checkClaim(Constants.USER_A_ADDRESS, OrderKeyForUserA, market.getOrder(OrderKeyForUserA).amount);
        _checkClaim(Constants.USER_B_ADDRESS, OrderKeyForUserB, 0);
    }

    function testBondScenario3() public {
        vm.warp(block.timestamp + 5000);
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
        assertEq(bondPool.availableAmount(), RELEASE_RATE_PER_SECOND * 5000);

        // A buy bond
        _checkPurchaseBond({
            amount: 10 ** 6,
            bonus: 5,
            user: Constants.USER_A_ADDRESS,
            expectedOrderIndex: 0,
            expectedSoldAmount: 11891207599903039367405
        });

        // A's order has been partially taken and implicitly claimed multiple times
        OrderKey memory OrderKeyForUserA = OrderKey({
            isBid: false,
            priceIndex: bondPool.getBasisPriceIndex() + 5,
            orderIndex: 0
        });
        uint256 orderId = CloberOrderNFT(market.orderToken()).encodeId(OrderKeyForUserA);
        uint256 beforeBondUSDC = usdcToken.balanceOf(address(bondPool));
        IBondPool.BondInfo memory beforeInfo = bondPool.bondInfo(orderId);
        uint64 rawAmountToTake = market.getOrder(OrderKeyForUserA).amount / 3;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: rawAmountToTake});
        market.claim(address(bondPool), _toArray(OrderKeyForUserA));
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: rawAmountToTake});
        market.claim(address(bondPool), _toArray(OrderKeyForUserA));
        uint256 usdcDiff = usdcToken.balanceOf(address(bondPool)) - beforeBondUSDC;

        // check the amount that A can claim
        IBondPool.BondInfo memory afterInfo = bondPool.bondInfo(orderId);
        assertEq(afterInfo.claimedAmount, beforeInfo.claimedAmount, "CLAIMED_AMOUNT");
        assertEq(afterInfo.bondedAmount, beforeInfo.bondedAmount, "BONDED_AMOUNT");
        assertEq(bondPool.claimable(orderId), usdcDiff, "CLAIMABLE");
    }
}
