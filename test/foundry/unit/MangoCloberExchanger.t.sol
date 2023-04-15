// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../contracts/MangoCloberExchanger.sol";
import "../../../contracts/clober/CloberRouter.sol";
import "../../mocks/MockToken.sol";
import "../../mocks/MockTokenReceiver.sol";
import "../CloberForkTestSetUp.sol";
import "../CloberOrderParamsBuilder.sol";

contract MangoCloberExchangerUnitTest is Test {
    event Receive(address indexed sender, uint256 amount);

    uint16 constant PRICE_INDEX = 1000;
    address constant PROXY_ADMIN = address(0x1231241);

    IERC20Metadata inputToken;
    IERC20Metadata outputToken;
    CloberRouter router;
    CloberOrderBook market;
    ITokenReceiver receiver;
    MangoCloberExchanger exchanger;

    function setUp() public {
        CloberForkTestSetUp fork = new CloberForkTestSetUp();
        (router, market) = fork.run();

        outputToken = IERC20Metadata(market.quoteToken());
        inputToken = IERC20Metadata(market.baseToken());
        receiver = new MockTokenReceiver(address(outputToken));
        address exchangerLogic = address(
            new MangoCloberExchanger(address(inputToken), address(outputToken), address(market))
        );
        exchanger = MangoCloberExchanger(
            address(
                new TransparentUpgradeableProxy(
                    exchangerLogic,
                    PROXY_ADMIN,
                    abi.encodeWithSelector(MangoCloberExchanger.initialize.selector, address(receiver))
                )
            )
        );
    }

    function testInitializeWithWrongReceiver() public {
        exchanger = new MangoCloberExchanger(address(inputToken), address(outputToken), address(market));
        receiver = new MockTokenReceiver(address(inputToken));
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        exchanger.initialize(address(receiver));
    }

    function testInitializeOnlyCalledOnce() public {
        vm.expectRevert("Initializable: contract is already initialized");
        exchanger.initialize(address(receiver));
    }

    function testReceivingToken() public {
        assertEq(exchanger.receivingToken(), address(inputToken));
    }

    function testMarket() public {
        assertEq(exchanger.market(), address(market));
    }

    function testTransferableAmount() public {
        assertEq(exchanger.transferableAmount(), 0);
    }

    function testReceiveToken() public {
        inputToken.approve(address(exchanger), 100);

        uint256 beforeBalance = inputToken.balanceOf(address(exchanger));
        vm.expectEmit(true, true, true, true);
        emit Receive(address(this), 100);
        exchanger.receiveToken(100);
        assertEq(inputToken.balanceOf(address(exchanger)) - beforeBalance, 100, "EXCHANGER_BALANCE");
    }

    function _resetBidExchanger() internal {
        exchanger = new MangoCloberExchanger(address(outputToken), address(inputToken), address(market));
        receiver = new MockTokenReceiver(address(inputToken));
        exchanger.initialize(address(receiver));
    }

    function testLimitOrderBid() public {
        _resetBidExchanger();
        outputToken.transfer(address(exchanger), 10**6);
        assertEq(exchanger.currentOrderId(), type(uint256).max, "BEFORE_ORDER_ID");

        vm.expectCall(
            address(market),
            abi.encodeCall(CloberOrderBook.limitOrder, (address(exchanger), PRICE_INDEX, 10**6, 0, 1, new bytes(0)))
        );
        exchanger.limitOrder(PRICE_INDEX);

        uint256 orderId = exchanger.currentOrderId();
        assertLt(orderId, type(uint256).max, "ORDER_ID");
        assertEq(CloberOrderNFT(market.orderToken()).ownerOf(orderId), address(exchanger), "ORDER_NFT");
        assertEq(inputToken.balanceOf(address(exchanger)), 0, "EXCHANGER_BALANCE");
    }

    function testLimitOrderAsk() public {
        inputToken.transfer(address(exchanger), 10**18);
        assertEq(exchanger.currentOrderId(), type(uint256).max, "BEFORE_ORDER_ID");

        uint256 expectedOrderAmount = market.rawToBase(market.baseToRaw(10**18, PRICE_INDEX, false), PRICE_INDEX, true);
        vm.expectCall(
            address(market),
            abi.encodeCall(CloberOrderBook.limitOrder, (address(exchanger), PRICE_INDEX, 0, 10**18, 0, new bytes(0)))
        );
        exchanger.limitOrder(PRICE_INDEX);

        uint256 orderId = exchanger.currentOrderId();
        assertLt(orderId, type(uint256).max, "ORDER_ID");
        assertEq(CloberOrderNFT(market.orderToken()).ownerOf(orderId), address(exchanger), "ORDER_NFT");
        assertEq(inputToken.balanceOf(address(exchanger)), 10**18 - expectedOrderAmount, "EXCHANGER_BALANCE");
    }

    function testLimitOrderAccess() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        exchanger.limitOrder(PRICE_INDEX);
    }

    function testLimitOrderShouldCancelPreviousOrder() public {
        inputToken.transfer(address(exchanger), 10**18);
        exchanger.limitOrder(PRICE_INDEX);
        uint256 orderId = exchanger.currentOrderId();
        assertLt(orderId, type(uint256).max, "BEFORE_ORDER_ID");

        inputToken.transfer(address(exchanger), 10**18);
        exchanger.limitOrder(PRICE_INDEX);
        uint256 newOrderId = exchanger.currentOrderId();
        assertFalse(orderId == newOrderId, "ORDER_ID");
        assertEq(CloberOrderNFT(market.orderToken()).balanceOf(address(exchanger)), 1, "ORDER_NFT_BALANCE");
        assertEq(CloberOrderNFT(market.orderToken()).ownerOf(newOrderId), address(exchanger), "ORDER_NFT_ID");
    }

    function testLimitOrderWithoutMakingOrder() public {
        router.limitBid(CloberOrderParamBuilder.buildBid(PRICE_INDEX, 100 * 10**(outputToken.decimals())));

        inputToken.transfer(address(exchanger), 10**18);
        assertEq(exchanger.currentOrderId(), type(uint256).max, "BEFORE_ORDER_ID");

        exchanger.limitOrder(PRICE_INDEX);

        assertEq(exchanger.currentOrderId(), type(uint256).max, "ORDER_ID");
        assertEq(CloberOrderNFT(market.orderToken()).balanceOf(address(exchanger)), 0, "ORDER_NFT_BALANCE");
        assertGt(outputToken.balanceOf(address(exchanger)), 0, "OUTPUT_TOKEN_BALANCE");
    }

    function testCloberCallbackAccess() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.ACCESS));
        vm.prank(address(1));
        exchanger.cloberMarketSwapCallback(address(inputToken), address(outputToken), 100, 0, new bytes(0));
    }

    function testCloberCallbackCalledByMarketWithWrongTokenPairs() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        vm.prank(address(market));
        exchanger.cloberMarketSwapCallback(address(inputToken), address(123), 100, 0, new bytes(0));

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        vm.prank(address(market));
        exchanger.cloberMarketSwapCallback(address(123), address(outputToken), 100, 0, new bytes(0));
    }

    function testTransferOutputToken() public {
        outputToken.transfer(address(exchanger), 100);

        uint256 beforeExchangerBalance = outputToken.balanceOf(address(exchanger));
        uint256 beforeReceiverBalance = outputToken.balanceOf(address(receiver));
        vm.expectCall(address(receiver), abi.encodeCall(ITokenReceiver.receiveToken, (beforeExchangerBalance)));
        exchanger.transferOutputToken();
        assertEq(outputToken.balanceOf(address(exchanger)), 0, "EXCHANGER_BALANCE");
        assertEq(
            outputToken.balanceOf(address(receiver)),
            beforeReceiverBalance + beforeExchangerBalance,
            "RECEIVER_BALANCE"
        );
    }

    function testTransferOutputTokenShouldClaimFirst() public {
        inputToken.transfer(address(exchanger), 10**18);
        exchanger.limitOrder(PRICE_INDEX);
        uint256 orderId = exchanger.currentOrderId();
        router.limitBid(CloberOrderParamBuilder.buildBid(PRICE_INDEX, 100 * 10**(outputToken.decimals())));
        (, uint256 claimable, , ) = market.getClaimable(CloberOrderNFT(market.orderToken()).decodeId(orderId));
        assertGt(claimable, 0, "CLAIMABLE");

        outputToken.transfer(address(exchanger), 10**(outputToken.decimals()));
        vm.expectCall(
            address(receiver),
            abi.encodeCall(ITokenReceiver.receiveToken, (claimable + 10**(outputToken.decimals())))
        );
        exchanger.transferOutputToken();

        assertEq(exchanger.currentOrderId(), orderId, "ORDER_ID");
        (, claimable, , ) = market.getClaimable(CloberOrderNFT(market.orderToken()).decodeId(orderId));
        assertEq(claimable, 0, "CLAIMABLE");
        assertEq(outputToken.balanceOf(address(exchanger)), 0, "EXCHANGER_BALANCE");
    }

    function testTransferOutputTokenWhenNoTokens() public {
        uint256 beforeExchangerBalance = outputToken.balanceOf(address(exchanger));
        assertEq(beforeExchangerBalance, 0, "BEFORE_EXCHANGER_BALANCE");
        uint256 beforeReceiverBalance = outputToken.balanceOf(address(receiver));
        exchanger.transferOutputToken();
        assertEq(beforeExchangerBalance, 0, "AFTER_EXCHANGER_BALANCE");
        assertEq(outputToken.balanceOf(address(receiver)), beforeReceiverBalance, "RECEIVER_BALANCE");
    }

    function testSetReceiver() public {
        ITokenReceiver newReceiver = new MockTokenReceiver(address(outputToken));
        exchanger.setReceiver(newReceiver);
        assertEq(address(exchanger.outputTokenReceiver()), address(newReceiver), "RECEIVER");
        assertEq(outputToken.allowance(address(exchanger), address(newReceiver)), type(uint256).max, "ALLOWANCE");
    }

    function testSetReceiverAccess() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        exchanger.setReceiver(ITokenReceiver(address(123)));
    }

    function testSetReceiverReceivingWrongToken() public {
        ITokenReceiver newReceiver = new MockTokenReceiver(address(inputToken));
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        exchanger.setReceiver(newReceiver);
    }

    function testWithdrawLostERC20() public {
        IERC20 lostToken = new MockToken(100);
        lostToken.transfer(address(exchanger), 100);

        uint256 beforeExchangerBalance = lostToken.balanceOf(address(exchanger));
        uint256 beforeThisBalance = lostToken.balanceOf(address(this));
        exchanger.withdrawLostERC20(address(lostToken), address(this));
        assertEq(lostToken.balanceOf(address(exchanger)), 0, "EXCHANGER_BALANCE");
        assertEq(lostToken.balanceOf(address(this)), beforeThisBalance + beforeExchangerBalance, "THIS_BALANCE");
    }

    function testWithdrawLostERC20Access() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        exchanger.withdrawLostERC20(address(2), address(1));
    }

    function testWithdrawLostERC20WithInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        exchanger.withdrawLostERC20(address(inputToken), address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        exchanger.withdrawLostERC20(address(outputToken), address(this));
    }

    function testWithdrawLostERC20WithEmptyBalance() public {
        IERC20 lostToken = new MockToken(100);

        uint256 beforeExchangerBalance = lostToken.balanceOf(address(exchanger));
        assertEq(beforeExchangerBalance, 0, "BEFORE_EXCHANGER_BALANCE");
        uint256 beforeThisBalance = lostToken.balanceOf(address(this));

        exchanger.withdrawLostERC20(address(lostToken), address(this));

        assertEq(beforeExchangerBalance, 0, "AFTER_EXCHANGER_BALANCE");
        assertEq(lostToken.balanceOf(address(this)), beforeThisBalance, "THIS_BALANCE");
    }
}
