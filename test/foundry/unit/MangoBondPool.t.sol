// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../CloberForkTestSetUp.sol";
import "../../../contracts/MangoBondPool.sol";
import "../../mocks/MockTokenReceiver.sol";
import "../../mocks/MockToken.sol";

contract MangoBondPoolUnitTest is Test {
    event PurchaseBond(
        address indexed payer,
        address indexed to,
        uint256 indexed orderId,
        uint256 spentAmount,
        uint8 bonus,
        uint256 bondedAmount
    );

    uint256 public constant CANCEL_FEE = 200000; // 20%
    uint256 public constant MAX_RELEASE_AMOUNT = 500_000_000 * (10 ** 18);
    uint256 public constant RELEASE_RATE_PER_SECOND = 11574074074074073088; // MAX_RELEASE_AMOUNT // (60 * 60 * 24 * 500)
    address public constant BURN_ADDRESS = address(0xdead);
    uint16 public constant INITIAL_BOND_PRICE_INDEX = 219; // log_1.01(0.000089 / 0.00001)
    address constant PROXY_ADMIN = address(0x1231241);

    // Clober
    CloberForkTestSetUp forkTestSetUp;
    CloberRouter router;
    CloberOrderBook market;
    CloberOrderNFT orderNFT;

    // Mango
    address treasury;
    address bondPoolLogic;
    MangoBondPool bondPool;
    ERC20 mangoToken;
    ERC20 usdcToken;

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

    function setUp() public {
        forkTestSetUp = new CloberForkTestSetUp();
        (router, market) = forkTestSetUp.run();
        orderNFT = CloberOrderNFT(market.orderToken());

        treasury = address(new MockTokenReceiver(Constants.USDC_ADDRESS));
        mangoToken = ERC20(Constants.MANGO_ADDRESS);
        usdcToken = ERC20(Constants.USDC_ADDRESS);

        bondPoolLogic = address(
            new MangoBondPool(
                treasury,
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
                    abi.encodeWithSelector(MangoBondPool.initialize.selector, 5, 15, uint64(block.timestamp), 10)
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
    }

    function testInitialize() public {
        MangoBondPool uninitializedBondPool = MangoBondPool(
            address(new TransparentUpgradeableProxy(bondPoolLogic, PROXY_ADMIN, new bytes(0)))
        );

        assertEq(uninitializedBondPool.minBonus(), 0, "BEFORE_MIN_BONUS");
        assertEq(uninitializedBondPool.maxBonus(), 0, "BEFORE_MAX_BONUS");
        assertEq(uninitializedBondPool.lastReleasedAt(), 0, "BEFORE_LAST_RELEASED_AT");
        assertEq(uninitializedBondPool.sampleSize(), 0, "BEFORE_SAMPLE_SIZE");
        assertEq(uninitializedBondPool.owner(), address(0), "BEFORE_OWNER");
        assertEq(usdcToken.allowance(address(uninitializedBondPool), treasury), 0, "BEFORE_ALLOWANCE");
        address initializer = address(0x1111);
        vm.prank(initializer);
        uninitializedBondPool.initialize(5, 15, uint64(block.timestamp), 10);
        assertEq(uninitializedBondPool.minBonus(), 5, "AFTER_MIN_BONUS");
        assertEq(uninitializedBondPool.maxBonus(), 15, "AFTER_MAX_BONUS");
        assertEq(uninitializedBondPool.lastReleasedAt(), block.timestamp, "AFTER_LAST_RELEASED_AT");
        assertEq(uninitializedBondPool.sampleSize(), 10, "AFTER_SAMPLE_SIZE");
        assertEq(uninitializedBondPool.owner(), initializer, "AFTER_OWNER");
        assertEq(usdcToken.allowance(address(uninitializedBondPool), treasury), type(uint256).max, "AFTER_ALLOWANCE");

        vm.expectRevert("Initializable: contract is already initialized");
        uninitializedBondPool.initialize(5, 15, uint64(block.timestamp), 10);
    }

    function testInitializeTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        bondPool.initialize(5, 15, uint64(block.timestamp), 10);
    }

    function testSetApprovals() public {
        vm.prank(address(bondPool));
        usdcToken.decreaseAllowance(treasury, type(uint256).max / 2);
        assertGt(usdcToken.allowance(address(bondPool), treasury), 0, "BEFORE");
        bondPool.setApprovals();
        assertEq(usdcToken.allowance(address(bondPool), treasury), type(uint256).max, "AFTER");
    }

    function testDoubleInitialization() public {
        vm.expectRevert("Initializable: contract is already initialized");
        bondPool.initialize(5, 15, uint64(block.timestamp), 10);
    }

    function testBondInfo() public {
        assertEq(bondPool.market(), Constants.MANGO_USDC_MARKET_ADDRESS, "ERROR_MARKET");
        assertEq(bondPool.treasury(), treasury, "ERROR_TREASURY");
    }

    function testCloberMarketSwapCallback() public {
        vm.warp(block.timestamp + 10);
        assertEq(bondPool.availableAmount(), RELEASE_RATE_PER_SECOND * 10);

        uint256 soldAmount = 10 ** 18;
        mangoToken.transfer(address(bondPool), soldAmount);

        vm.prank(Constants.MANGO_USDC_MARKET_ADDRESS);
        bondPool.cloberMarketSwapCallback(Constants.MANGO_ADDRESS, Constants.USDC_ADDRESS, soldAmount, 0, new bytes(0));
        assertEq(bondPool.availableAmount(), RELEASE_RATE_PER_SECOND * 10 - soldAmount);
    }

    function testCloberMarketSwapCallbackAccess() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.ACCESS));
        bondPool.cloberMarketSwapCallback(Constants.MANGO_ADDRESS, Constants.USDC_ADDRESS, 0, 0, new bytes(0));
    }

    function testCloberMarketSwapCallbackInvalidAddress() public {
        vm.prank(Constants.MANGO_USDC_MARKET_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        bondPool.cloberMarketSwapCallback(Constants.MANGO_ADDRESS, address(0), 0, 0, new bytes(0));

        vm.prank(Constants.MANGO_USDC_MARKET_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        bondPool.cloberMarketSwapCallback(address(0), Constants.USDC_ADDRESS, 0, 0, new bytes(0));
    }

    function testWithdrawLostERC20() public {
        mangoToken.transfer(address(bondPool), 10 ** 18);
        usdcToken.transfer(address(bondPool), 10 ** 6);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        bondPool.withdrawLostERC20(address(mangoToken), address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        bondPool.withdrawLostERC20(address(usdcToken), address(this));

        MockToken mockToken = new MockToken(10000 * 10 ** 18);
        mockToken.transfer(address(bondPool), 10000 * 10 ** 18);

        vm.prank(Constants.USER_A_ADDRESS);
        vm.expectRevert("Ownable: caller is not the owner");
        bondPool.withdrawLostERC20(address(mockToken), address(this));

        uint256 beforeBalance = mockToken.balanceOf(address(this));
        bondPool.withdrawLostERC20(address(mockToken), address(this));
        assertEq(mockToken.balanceOf(address(this)), beforeBalance + 10000 * 10 ** 18);
    }

    function testChangeBonusRange() public {
        assertEq(bondPool.minBonus(), 5);
        assertEq(bondPool.maxBonus(), 15);

        bondPool.changeAvailableBonusRange(10, 20);
        assertEq(bondPool.minBonus(), 10);
        assertEq(bondPool.maxBonus(), 20);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_BONUS));
        bondPool.changeAvailableBonusRange(20, 10);

        vm.prank(Constants.USDC_ADDRESS);
        vm.expectRevert("Ownable: caller is not the owner");
        bondPool.changeAvailableBonusRange(10, 20);
    }

    function testChangeOracleWindow() public {
        assertEq(bondPool.sampleSize(), 10);
        bondPool.changePriceSampleSize(15);
        assertEq(bondPool.sampleSize(), 15);

        vm.prank(Constants.USDC_ADDRESS);
        vm.expectRevert("Ownable: caller is not the owner");
        bondPool.changePriceSampleSize(10);
    }

    function testGetBasisPriceIndexWhenZeroSize() public {
        bondPool.changePriceSampleSize(0);
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
    }

    function testGetBasisPriceIndexWhenEmpty() public {
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);

        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);

        vm.warp(block.timestamp + 1);
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: 10 ** 6});
        _createLimitOrder({isBid: false, priceIndex: 8000, rawAmount: 10 ** 6});
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
    }

    function testGetBasisPriceIndexSkippingSameBlock() public {
        for (uint16 i = 0; i < 9; i++) {
            vm.warp(block.timestamp + 1);
            _createLimitOrder({isBid: true, priceIndex: INITIAL_BOND_PRICE_INDEX + i, rawAmount: 10 ** 6});
            _createLimitOrder({isBid: false, priceIndex: INITIAL_BOND_PRICE_INDEX + i, rawAmount: 10 ** 6});
            if (i != 0) {
                assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX + i - 1);
            } else {
                assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
            }
        }

        vm.warp(block.timestamp + 1);
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: 10 ** 6});
        _createLimitOrder({isBid: false, priceIndex: 8000, rawAmount: 10 ** 6});
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX + 8);

        vm.warp(block.timestamp + 1);
        assertEq(bondPool.getBasisPriceIndex(), 8000);
    }

    function testExpectedBondAmount() public {
        uint256 usdcAmount = 2 * 10 ** 6;
        uint8 bonus = 5;
        uint256 expectedBondAmount = bondPool.expectedBondAmount(usdcAmount, bonus);
        assertEq(expectedBondAmount, 23782415199806078734810);
    }

    function testExpectedBondAmountWithInvalidBonus() public {
        uint256 usdcAmount = 2 * 10 ** 6;

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_BONUS));
        bondPool.expectedBondAmount(usdcAmount, 4);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_BONUS));
        bondPool.expectedBondAmount(usdcAmount, 16);
    }

    function testReleasedAmount() public {
        uint256 firstBlockTimestamp = block.timestamp;

        assertEq(bondPool.releasedAmount(), 0);

        vm.warp(block.timestamp + 1);
        assertEq(bondPool.releasedAmount(), RELEASE_RATE_PER_SECOND);

        vm.warp(block.timestamp + 1);
        assertEq(bondPool.releasedAmount(), RELEASE_RATE_PER_SECOND * 2);

        vm.warp(firstBlockTimestamp + 500 days - 1);
        assertEq(bondPool.releasedAmount(), RELEASE_RATE_PER_SECOND * (500 days - 1));

        vm.warp(firstBlockTimestamp + 500 days);
        assertEq(bondPool.releasedAmount(), RELEASE_RATE_PER_SECOND * 500 days);

        vm.warp(firstBlockTimestamp + 510 days);
        assertEq(bondPool.releasedAmount(), MAX_RELEASE_AMOUNT);
    }

    function testPurchaseBondWhenPaused() public {
        bondPool.pause();
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.PAUSED));
        bondPool.purchaseBond(10 ** 6, 6, Constants.USER_A_ADDRESS, type(uint16).max);
    }

    function testPurchaseBondRevertToInsufficientBalance() public {
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INSUFFICIENT_BALANCE));
        bondPool.purchaseBond(10 ** 6, 6, Constants.USER_A_ADDRESS, type(uint16).max);
    }

    function testDoublePurchaseBond() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 2 * 10 ** 6;
        bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INSUFFICIENT_BALANCE));
        bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);
    }

    function testPurchaseBondRevertWithInvalidBonus() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);

        vm.warp(block.timestamp + 3000);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_BONUS));
        bondPool.purchaseBond(10 ** 6, 4, Constants.USER_A_ADDRESS, INITIAL_BOND_PRICE_INDEX + 4);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_BONUS));
        bondPool.purchaseBond(10 ** 6, 16, Constants.USER_A_ADDRESS, INITIAL_BOND_PRICE_INDEX + 4);
    }

    function testPurchaseBondRevertToSlippage() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);

        vm.warp(block.timestamp + 3000);
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
        assertEq(bondPool.availableAmount(), RELEASE_RATE_PER_SECOND * 3000);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.SLIPPAGE));
        bondPool.purchaseBond(10 ** 6, 5, Constants.USER_A_ADDRESS, INITIAL_BOND_PRICE_INDEX + 4);
    }

    function testPurchaseBondRevertToTooInvalidOrderIndex() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        bondPool.changePriceSampleSize(1);
        uint16 highPriceIndex = 6000;
        _createLimitOrder({isBid: true, priceIndex: highPriceIndex, rawAmount: 10 ** 6});
        _createLimitOrder({isBid: false, priceIndex: highPriceIndex, rawAmount: 10 ** 6});

        vm.warp(block.timestamp + 3000);
        assertEq(bondPool.getBasisPriceIndex(), highPriceIndex);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.AMOUNT_TOO_SMALL));
        bondPool.purchaseBond(10 ** 6, 5, Constants.USER_A_ADDRESS, type(uint16).max);
    }

    function testPurchaseBondRevertToAmountTooSmall() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        bondPool.changePriceSampleSize(1);
        uint16 highPriceIndex = 5300;
        _createLimitOrder({isBid: true, priceIndex: highPriceIndex, rawAmount: 10 ** 6});
        _createLimitOrder({isBid: false, priceIndex: highPriceIndex, rawAmount: 10 ** 6});

        vm.warp(block.timestamp + 3000);
        assertEq(bondPool.getBasisPriceIndex(), highPriceIndex);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.AMOUNT_TOO_SMALL));
        bondPool.purchaseBond(10 ** 6, 5, Constants.USER_A_ADDRESS, type(uint16).max);
    }

    function testPurchaseBondSuccess() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);

        vm.warp(block.timestamp + 3000);
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
        assertEq(bondPool.availableAmount(), RELEASE_RATE_PER_SECOND * 3000);

        uint256 beforeUSDCBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        uint256 usdcAmount = 10 ** 6;
        uint8 bonus = 5;
        uint256 expectedSoldAmount = 11891207599903039367405;

        vm.expectEmit(true, true, false, true);
        emit PurchaseBond(
            Constants.USER_A_ADDRESS,
            Constants.USER_A_ADDRESS,
            orderNFT.encodeId(OrderKey({isBid: false, priceIndex: INITIAL_BOND_PRICE_INDEX + bonus, orderIndex: 0})),
            usdcAmount,
            bonus,
            expectedSoldAmount
        );
        vm.prank(Constants.USER_A_ADDRESS);
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);
        assertEq(
            orderId,
            orderNFT.encodeId(OrderKey({isBid: false, priceIndex: INITIAL_BOND_PRICE_INDEX + bonus, orderIndex: 0})),
            "ERROR_ORDER_ID"
        );
        assertEq(
            market
                .getOrder(OrderKey({isBid: false, priceIndex: INITIAL_BOND_PRICE_INDEX + bonus, orderIndex: 0}))
                .amount,
            market.baseToRaw(expectedSoldAmount, INITIAL_BOND_PRICE_INDEX + bonus, true),
            "ERROR_AMOUNT_ORDER"
        );
        assertEq(beforeUSDCBalance - usdcToken.balanceOf(Constants.USER_A_ADDRESS), usdcAmount, "ERROR_USDC_BALANCE");
        assertEq(usdcToken.balanceOf(address(treasury)), usdcAmount, "ERROR_USDC_BALANCE_TREASURY");

        // check Bond info
        IBondPool.BondInfo memory bond = bondPool.bondInfo(orderId);
        assertEq(bond.orderId, orderId, "ERROR_BOND_ORDER_ID");
        assertEq(bond.owner, Constants.USER_A_ADDRESS, "ERROR_BOND_OWNER");
        assertEq(bond.bonus, bonus, "ERROR_BOND_BONUS");
        assertEq(bond.isValid, true, "ERROR_BOND_IS_VALID");
        assertEq(bond.spentAmount, usdcAmount, "ERROR_BOND_SPENT_AMOUNT");
        assertEq(bond.bondedAmount, expectedSoldAmount, "ERROR_BOND_BONDED_AMOUNT");
        assertEq(bond.claimedAmount, 0, "ERROR_BOND_CLAIMED_AMOUNT");
        assertEq(bond.canceledAmount, 0, "ERROR_BOND_CANCELED_AMOUNT");
        assertEq(bondPool.ownerOf(orderId), Constants.USER_A_ADDRESS, "ERROR_BOND_OWNER_OF");

        assertEq(orderNFT.balanceOf(address(bondPool)), 1, "ERROR_ORDER_NFT_BALANCE_OF");
        assertEq(orderNFT.balanceOf(Constants.USER_A_ADDRESS), 0, "ERROR_ORDER_NFT_BALANCE_OF");
        assertEq(orderNFT.balanceOf(Constants.USER_B_ADDRESS), 0, "ERROR_ORDER_NFT_BALANCE_OF");
    }

    function testPurchaseByOther() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);

        vm.warp(block.timestamp + 3000);
        assertEq(bondPool.getBasisPriceIndex(), INITIAL_BOND_PRICE_INDEX);
        assertEq(bondPool.availableAmount(), RELEASE_RATE_PER_SECOND * 3000);

        uint256 beforeUSDCBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        uint256 usdcAmount = 10 ** 6;
        uint8 bonus = 5;
        uint256 expectedSoldAmount = 11891207599903039367405;

        vm.expectEmit(true, true, false, true);
        emit PurchaseBond(
            Constants.USER_A_ADDRESS,
            Constants.USER_B_ADDRESS,
            orderNFT.encodeId(OrderKey({isBid: false, priceIndex: INITIAL_BOND_PRICE_INDEX + bonus, orderIndex: 0})),
            usdcAmount,
            bonus,
            expectedSoldAmount
        );
        vm.prank(Constants.USER_A_ADDRESS);
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_B_ADDRESS, type(uint16).max);
        assertEq(
            orderId,
            orderNFT.encodeId(OrderKey({isBid: false, priceIndex: INITIAL_BOND_PRICE_INDEX + bonus, orderIndex: 0})),
            "ERROR_ORDER_ID"
        );
        assertEq(
            beforeUSDCBalance - usdcToken.balanceOf(Constants.USER_A_ADDRESS),
            usdcAmount,
            "ERROR_PAYER_USDC_BALANCE"
        );
        assertEq(usdcToken.balanceOf(address(treasury)), usdcAmount, "ERROR_USDC_BALANCE_TREASURY");

        // check Bond info
        IBondPool.BondInfo memory bond = bondPool.bondInfo(orderId);
        assertEq(bond.orderId, orderId, "ERROR_BOND_ORDER_ID");
        assertEq(bond.owner, Constants.USER_B_ADDRESS, "ERROR_BOND_OWNER");
        assertEq(bond.bonus, bonus, "ERROR_BOND_BONUS");
        assertEq(bond.isValid, true, "ERROR_BOND_IS_VALID");
        assertEq(bond.spentAmount, usdcAmount, "ERROR_BOND_SPENT_AMOUNT");
        assertEq(bond.bondedAmount, expectedSoldAmount, "ERROR_BOND_BONDED_AMOUNT");
        assertEq(bond.claimedAmount, 0, "ERROR_BOND_CLAIMED_AMOUNT");
        assertEq(bond.canceledAmount, 0, "ERROR_BOND_CANCELED_AMOUNT");
        assertEq(bondPool.ownerOf(orderId), Constants.USER_B_ADDRESS, "ERROR_BOND_OWNER_OF");
        assertEq(orderNFT.ownerOf(orderId), address(bondPool), "ERROR_ORDER_NFT_OWNER_OF");

        assertEq(orderNFT.balanceOf(address(bondPool)), 1, "ERROR_ORDER_NFT_BALANCE_OF");
        assertEq(orderNFT.balanceOf(Constants.USER_A_ADDRESS), 0, "ERROR_ORDER_NFT_BALANCE_OF");
        assertEq(orderNFT.balanceOf(Constants.USER_B_ADDRESS), 0, "ERROR_ORDER_NFT_BALANCE_OF");
    }

    function testClaimWhenPause() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint256 orderId = bondPool.purchaseBond(10 ** 6, 5, Constants.USER_A_ADDRESS, type(uint16).max);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;

        bondPool.pause();
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.PAUSED));
        bondPool.claim(orderIds);
    }

    function testNothingToClaim() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint256 orderId = bondPool.purchaseBond(10 ** 6, 5, Constants.USER_A_ADDRESS, type(uint16).max);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;

        uint256 beforeMangoBalance = mangoToken.balanceOf(Constants.USER_A_ADDRESS);
        bondPool.claim(orderIds);
        assertEq(mangoToken.balanceOf(Constants.USER_A_ADDRESS), beforeMangoBalance, "ERROR_MANGO_BALANCE");
    }

    function testUnaccountedClaimedAmount() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 10 ** 6;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        OrderKey memory orderKey = OrderKey({
            isBid: false,
            priceIndex: INITIAL_BOND_PRICE_INDEX + bonus,
            orderIndex: 0
        });
        uint64 orderRawAmount = market.getOrder(orderKey).amount;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: orderRawAmount / 4});

        OrderKey[] memory orderKeyList = new OrderKey[](1);
        orderKeyList[0] = OrderKey({isBid: false, priceIndex: INITIAL_BOND_PRICE_INDEX + bonus, orderIndex: 0});

        vm.prank(Constants.USER_A_ADDRESS);
        market.claim(Constants.USER_A_ADDRESS, orderKeyList);
        assertEq(bondPool.unaccountedClaimedAmount(orderId), orderRawAmount / 4, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");

        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: orderRawAmount / 4});
        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.claim(orderIds);
        assertEq(bondPool.unaccountedClaimedAmount(orderId), 0, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");
    }

    function testClaimInFullyFilledOrder() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 10 ** 6;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        OrderKey memory orderKey = OrderKey({
            isBid: false,
            priceIndex: INITIAL_BOND_PRICE_INDEX + bonus,
            orderIndex: 0
        });
        uint64 orderRawAmount = market.getOrder(orderKey).amount;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: orderRawAmount});
        (uint256 claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, orderRawAmount, "ERROR_CLAIMABLE_AMOUNT");

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        assertEq(bondPool.claimable(orderId), claimableRawAmount, "ERROR_CLAIMABLE_AMOUNT");
        // check `implicitlyClaimedAmount`
        assertEq(bondPool.unaccountedClaimedAmount(orderId), 0, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");
        uint256 beforeUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.claim(orderIds);
        uint256 gainUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS) - beforeUsdcBalance;
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus)) / 100);
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus) * (100 + bonus)) / 10000);
    }

    function testDoubleClaim() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 10 ** 6;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        OrderKey memory orderKey = OrderKey({
            isBid: false,
            priceIndex: INITIAL_BOND_PRICE_INDEX + bonus,
            orderIndex: 0
        });
        uint64 orderRawAmount = market.getOrder(orderKey).amount;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: orderRawAmount});
        (uint256 claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, orderRawAmount, "ERROR_CLAIMABLE_AMOUNT");

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        assertEq(bondPool.claimable(orderId), claimableRawAmount, "ERROR_CLAIMABLE_AMOUNT");
        // check `implicitlyClaimedAmount`
        assertEq(bondPool.unaccountedClaimedAmount(orderId), 0, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");
        uint256 beforeUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.claim(orderIds);
        uint256 gainUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS) - beforeUsdcBalance;
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus)) / 100);
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus) * (100 + bonus)) / 10000);

        assertEq(bondPool.claimable(orderId), 0, "ERROR_CLAIMABLE_AMOUNT");
        beforeUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.claim(orderIds);
        assertEq(usdcToken.balanceOf(Constants.USER_A_ADDRESS), beforeUsdcBalance, "ERROR_USDC_BALANCE");
    }

    function testClaimInHalfFilledOrder() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 10 ** 6;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        OrderKey memory orderKey = OrderKey({
            isBid: false,
            priceIndex: INITIAL_BOND_PRICE_INDEX + bonus,
            orderIndex: 0
        });
        uint64 halfOrderRawAmount = market.getOrder(orderKey).amount / 2;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: halfOrderRawAmount});
        (uint256 claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, halfOrderRawAmount, "ERROR_CLAIMABLE_AMOUNT");

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        assertEq(bondPool.claimable(orderId), claimableRawAmount, "ERROR_CLAIMABLE_AMOUNT");
        // check `implicitlyClaimedAmount`
        assertEq(bondPool.unaccountedClaimedAmount(orderId), 0, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");
        uint256 beforeUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.claim(orderIds);
        uint256 gainUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS) - beforeUsdcBalance;
        assertGt(gainUsdcBalance, ((usdcAmount / 2) * (100 + bonus)) / 100);
        assertGt(gainUsdcBalance, ((usdcAmount / 2) * (100 + bonus) * (100 + bonus)) / 10000);
    }

    function testFullyClaimedByOther() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 10 ** 6;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        OrderKey memory orderKey = OrderKey({
            isBid: false,
            priceIndex: INITIAL_BOND_PRICE_INDEX + bonus,
            orderIndex: 0
        });
        uint64 orderRawAmount = market.getOrder(orderKey).amount;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: orderRawAmount});
        (uint256 claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, orderRawAmount, "ERROR_CLAIMABLE_AMOUNT");

        OrderKey[] memory orderKeyList = new OrderKey[](1);
        orderKeyList[0] = OrderKey({isBid: false, priceIndex: INITIAL_BOND_PRICE_INDEX + bonus, orderIndex: 0});
        uint256 beforeUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        market.claim(Constants.USER_A_ADDRESS, orderKeyList);
        assertEq(usdcToken.balanceOf(Constants.USER_A_ADDRESS), beforeUsdcBalance); // important

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        assertEq(bondPool.claimable(orderId), claimableRawAmount, "ERROR_CLAIMABLE_AMOUNT");
        // check `implicitlyClaimedAmount`
        assertEq(bondPool.unaccountedClaimedAmount(orderId), claimableRawAmount, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.claim(orderIds);

        (claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, 0, "ERROR_CLAIMABLE_AMOUNT_FINAL");

        uint256 gainUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS) - beforeUsdcBalance;
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus)) / 100);
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus) * (100 + bonus)) / 10000);
    }

    function testHalfClaimedByOther() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 10 ** 6;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        OrderKey memory orderKey = OrderKey({
            isBid: false,
            priceIndex: INITIAL_BOND_PRICE_INDEX + bonus,
            orderIndex: 0
        });
        uint64 totalRawAmount = market.getOrder(orderKey).amount;
        uint64 halfOrderRawAmount = market.getOrder(orderKey).amount / 2;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: halfOrderRawAmount});
        (uint256 claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, halfOrderRawAmount, "ERROR_CLAIMABLE_AMOUNT1");

        OrderKey[] memory orderKeyList = new OrderKey[](1);
        orderKeyList[0] = OrderKey({isBid: false, priceIndex: INITIAL_BOND_PRICE_INDEX + bonus, orderIndex: 0});
        uint256 beforeUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        market.claim(Constants.USER_A_ADDRESS, orderKeyList);

        halfOrderRawAmount = market.getOrder(orderKey).amount;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: halfOrderRawAmount});
        (claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, halfOrderRawAmount, "ERROR_CLAIMABLE_AMOUNT2");

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        assertEq(bondPool.claimable(orderId), totalRawAmount, "ERROR_CLAIMABLE_AMOUNT");
        // check `implicitlyClaimedAmount`
        assertEq(bondPool.unaccountedClaimedAmount(orderId), claimableRawAmount, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.claim(orderIds);

        (claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, 0, "ERROR_CLAIMABLE_AMOUNT_FINAL");

        uint256 gainUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS) - beforeUsdcBalance;
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus)) / 100);
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus) * (100 + bonus)) / 10000);
    }

    function tesCancelWhenPaused() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint256 orderId = bondPool.purchaseBond(1000, 5, Constants.USER_A_ADDRESS, type(uint16).max);

        bondPool.pause();
        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        vm.prank(Constants.USER_B_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.PAUSED));
        bondPool.breakBonds(orderIds);
    }

    function testCancelRevertToAccess() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint256 orderId = bondPool.purchaseBond(1000, 5, Constants.USER_A_ADDRESS, type(uint16).max);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        vm.prank(Constants.USER_B_ADDRESS);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.ACCESS));
        bondPool.breakBonds(orderIds);
    }

    function testCancelWhenNothingToClaim() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 123123;
        uint256 expectedSoldAmount = 1464066356825785710483;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        // check `implicitlyClaimedAmount`
        assertEq(bondPool.unaccountedClaimedAmount(orderId), 0, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");
        uint256 usdcBalanceBefore = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.breakBonds(orderIds);
        assertEq(
            mangoToken.balanceOf(Constants.USER_A_ADDRESS),
            (expectedSoldAmount * (1000000 - CANCEL_FEE)) / 1000000,
            "ERROR_USER_MANGO_BALANCE"
        );
        assertEq(
            mangoToken.balanceOf(BURN_ADDRESS),
            (expectedSoldAmount * CANCEL_FEE) / 1000000 + 1,
            "ERROR_BURNER_MANGO_BALANCE"
        );
        assertEq(usdcToken.balanceOf(Constants.USER_A_ADDRESS) - usdcBalanceBefore, 0, "ERROR_USER_USDC_BALANCE");
    }

    function testCancelWhenFullyFilled() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 10 ** 6;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        OrderKey memory orderKey = OrderKey({
            isBid: false,
            priceIndex: INITIAL_BOND_PRICE_INDEX + bonus,
            orderIndex: 0
        });
        uint64 orderRawAmount = market.getOrder(orderKey).amount;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: orderRawAmount});
        (uint256 claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, orderRawAmount, "ERROR_CLAIMABLE_AMOUNT");

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        assertEq(bondPool.claimable(orderId), orderRawAmount, "ERROR_CLAIMABLE_AMOUNT");
        // check `implicitlyClaimedAmount`
        assertEq(bondPool.unaccountedClaimedAmount(orderId), 0, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");
        uint256 beforeUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.breakBonds(orderIds);
        uint256 gainUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS) - beforeUsdcBalance;
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus)) / 100);
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus) * (100 + bonus)) / 10000);
    }

    function testDoubleCancel() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 10 ** 6;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        OrderKey memory orderKey = OrderKey({
            isBid: false,
            priceIndex: INITIAL_BOND_PRICE_INDEX + bonus,
            orderIndex: 0
        });
        uint64 orderRawAmount = market.getOrder(orderKey).amount;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: orderRawAmount});
        (uint256 claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, orderRawAmount, "ERROR_CLAIMABLE_AMOUNT");

        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        assertEq(bondPool.claimable(orderId), orderRawAmount, "ERROR_CLAIMABLE_AMOUNT");
        // check `implicitlyClaimedAmount`
        assertEq(bondPool.unaccountedClaimedAmount(orderId), 0, "ERROR_IMPLICITLY_CLAIMED_AMOUNT");
        uint256 beforeUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.breakBonds(orderIds);
        uint256 gainUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS) - beforeUsdcBalance;
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus)) / 100);
        assertGt(gainUsdcBalance, (usdcAmount * (100 + bonus) * (100 + bonus)) / 10000);

        assertEq(bondPool.claimable(orderId), 0, "ERROR_CLAIMABLE_AMOUNT");
        beforeUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.breakBonds(orderIds);
        assertEq(usdcToken.balanceOf(Constants.USER_A_ADDRESS), beforeUsdcBalance, "ERROR_USDC_BALANCE");
    }

    function testCancelWhenHalfClaimed() public {
        mangoToken.transfer(address(bondPool), 1000000 * 10 ** 18);
        vm.warp(block.timestamp + 3000);
        vm.prank(Constants.USER_A_ADDRESS);
        uint8 bonus = 5;
        uint256 usdcAmount = 10 ** 6;
        uint256 expectedSoldAmount = 5945603799951519683702;
        uint256 orderId = bondPool.purchaseBond(usdcAmount, bonus, Constants.USER_A_ADDRESS, type(uint16).max);

        OrderKey memory orderKey = OrderKey({
            isBid: false,
            priceIndex: INITIAL_BOND_PRICE_INDEX + bonus,
            orderIndex: 0
        });
        uint64 halfOrderRawAmount = market.getOrder(orderKey).amount / 2;
        _createLimitOrder({isBid: true, priceIndex: 8000, rawAmount: halfOrderRawAmount});
        (uint256 claimableRawAmount, , , ) = market.getClaimable(orderKey);
        assertEq(claimableRawAmount, halfOrderRawAmount, "ERROR_CLAIMABLE_AMOUNT");

        uint256 usdcBalanceBefore = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        uint256 mangoBalanceBefore = mangoToken.balanceOf(Constants.USER_A_ADDRESS);
        uint256[] memory orderIds = new uint256[](1);
        orderIds[0] = orderId;
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.claim(orderIds);
        uint256 gainUsdcBalance = usdcToken.balanceOf(Constants.USER_A_ADDRESS) - usdcBalanceBefore;
        assertGt(gainUsdcBalance, ((usdcAmount / 2) * (100 + bonus)) / 100);
        assertGt(gainUsdcBalance, ((usdcAmount / 2) * (100 + bonus) * (100 + bonus)) / 10000);
        assertEq(mangoToken.balanceOf(Constants.USER_A_ADDRESS), mangoBalanceBefore, "ERROR_MANGO_BALANCE");

        usdcBalanceBefore = usdcToken.balanceOf(Constants.USER_A_ADDRESS);
        mangoBalanceBefore = mangoToken.balanceOf(Constants.USER_A_ADDRESS);
        vm.prank(Constants.USER_A_ADDRESS);
        bondPool.breakBonds(orderIds);
        assertEq(
            mangoToken.balanceOf(Constants.USER_A_ADDRESS) - mangoBalanceBefore,
            (expectedSoldAmount * (1000000 - CANCEL_FEE)) / 1000000,
            "ERROR_USER_MANGO_BALANCE"
        );
        assertEq(
            mangoToken.balanceOf(BURN_ADDRESS),
            (expectedSoldAmount * CANCEL_FEE) / 1000000 + 1,
            "ERROR_BURNER_MANGO_BALANCE"
        );
        assertEq(usdcToken.balanceOf(Constants.USER_A_ADDRESS), usdcBalanceBefore, "ERROR_USDC_BALANCE");
    }
}
