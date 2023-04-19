// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../mocks/MockUSDC.sol";
import "../../mocks/MockStakedToken.sol";
import "../../mocks/MockToken.sol";
import "../../../contracts/MangoTreasury.sol";
import "../../../contracts/Errors.sol";

contract MangoTreasuryUnitTest is Test {
    event Distribute(uint256 amount, uint256 elapsed);
    event Receive(address indexed sender, uint256 amount);

    uint256 constant REWARD_RATE_RECIPROCAL = 1000 * 1 days;
    uint256 public constant INITIAL_USDC_SUPPLY = 1_000_000_000 * (10 ** 6);
    uint256 public constant TREASURY_REWARD_STARTS_AT = 100;
    uint256 public constant INITIAL_BLOCK_TIMESTAMP = 10;
    address constant PROXY_ADMIN = address(0x1231241);

    IStakedToken mangoStakedToken;
    IERC20 usdcToken;
    address mangoUsdcTreasuryLogic;
    MangoTreasury mangoUsdcTreasury;

    function setUp() public {
        vm.warp(INITIAL_BLOCK_TIMESTAMP);
        mangoStakedToken = IStakedToken(address(new MockStakedToken()));
        usdcToken = new MockUSDC(INITIAL_USDC_SUPPLY);
        mangoUsdcTreasuryLogic = address(new MangoTreasury(address(mangoStakedToken), address(usdcToken)));
        mangoUsdcTreasury = MangoTreasury(
            address(
                new TransparentUpgradeableProxy(
                    mangoUsdcTreasuryLogic,
                    PROXY_ADMIN,
                    abi.encodeWithSelector(MangoTreasury.initialize.selector, TREASURY_REWARD_STARTS_AT)
                )
            )
        );
    }

    function _divideCeil(uint256 x, uint256 y) private pure returns (uint256) {
        return (x + y - 1) / y;
    }

    function testInitialize() public {
        MangoTreasury newMangoUsdcTreasury = MangoTreasury(
            address(new TransparentUpgradeableProxy(mangoUsdcTreasuryLogic, PROXY_ADMIN, new bytes(0)))
        );

        assertEq(newMangoUsdcTreasury.lastDistributedAt(), 0, "BEFORE_LAST_RELEASED_AT");
        assertEq(newMangoUsdcTreasury.owner(), address(0), "BEFORE_OWNER");
        assertEq(usdcToken.allowance(address(newMangoUsdcTreasury), address(mangoStakedToken)), 0, "BEFORE_ALLOWANCE");
        address initializer = address(0x1111);
        vm.prank(initializer);
        newMangoUsdcTreasury.initialize(TREASURY_REWARD_STARTS_AT);
        assertEq(newMangoUsdcTreasury.lastDistributedAt(), TREASURY_REWARD_STARTS_AT, "AFTER_LAST_RELEASED_AT");
        assertEq(newMangoUsdcTreasury.owner(), initializer, "AFTER_OWNER");
        assertEq(
            usdcToken.allowance(address(newMangoUsdcTreasury), address(mangoStakedToken)),
            type(uint256).max,
            "AFTER_ALLOWANCE"
        );
    }

    function testSetApprovals() public {
        MangoTreasury newMangoUsdcTreasury = new MangoTreasury(address(mangoStakedToken), address(usdcToken));

        vm.prank(address(mangoUsdcTreasury));
        usdcToken.approve(address(mangoStakedToken), type(uint256).max / 2);

        assertEq(
            usdcToken.allowance(address(mangoUsdcTreasury), address(mangoStakedToken)),
            type(uint256).max / 2,
            "BEFORE"
        );
        mangoUsdcTreasury.setApprovals();
        assertEq(
            usdcToken.allowance(address(mangoUsdcTreasury), address(mangoStakedToken)),
            type(uint256).max,
            "AFTER"
        );
    }

    function testRewardRate() public {
        uint256 rewardRate = mangoUsdcTreasury.rewardRate();
        assertEq(rewardRate, 0, "initial rewardRate should be 0");
    }

    function testGetDistributableAmount() public {
        vm.warp(TREASURY_REWARD_STARTS_AT);

        uint256 distributableAmount = mangoUsdcTreasury.getDistributableAmount();
        assertEq(distributableAmount, 0, "initial distributableAmount should be 0");
    }

    function testGetDistributableAmountBeforeStartsAt() public {
        vm.warp(TREASURY_REWARD_STARTS_AT - 10);

        uint256 distributableAmount = mangoUsdcTreasury.getDistributableAmount();
        assertEq(distributableAmount, 0, "distributableAmount before startsAt should be 0");
    }

    function testReceivingToken() public {
        assertEq(address(mangoUsdcTreasury.receivingToken()), address(usdcToken), "receivingToken should be usdcToken");
    }

    function testDistribute() public {
        uint256 usdcBalance = 10000 * 10 ** 6;
        usdcToken.transfer(address(mangoUsdcTreasury), usdcBalance);
        uint256 current = TREASURY_REWARD_STARTS_AT + 10;
        vm.warp(current);

        assertEq(mangoUsdcTreasury.lastDistributedAt(), TREASURY_REWARD_STARTS_AT);
        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), usdcBalance);
        assertEq(usdcToken.balanceOf(address(mangoStakedToken)), 0);

        uint256 expectedDistributeAmount = (usdcBalance * 10) / REWARD_RATE_RECIPROCAL;
        vm.expectEmit(false, false, false, true);
        emit Distribute(expectedDistributeAmount, current - TREASURY_REWARD_STARTS_AT);
        // distribute expectedDistributeAmount
        mangoUsdcTreasury.distribute();

        assertEq(mangoUsdcTreasury.lastDistributedAt(), current);
        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), usdcBalance - expectedDistributeAmount);
        assertEq(usdcToken.balanceOf(address(mangoStakedToken)), expectedDistributeAmount);

        // distribute with 0 amount;
        mangoUsdcTreasury.distribute();

        assertEq(mangoUsdcTreasury.lastDistributedAt(), current);
        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), usdcBalance - expectedDistributeAmount);
        assertEq(usdcToken.balanceOf(address(mangoStakedToken)), expectedDistributeAmount);

        // transfer small amount of usdc to mangoUsdcTreasury
        // distribute after 17 seconds
        usdcToken.transfer(address(mangoUsdcTreasury), 41);
        usdcBalance = usdcToken.balanceOf(address(mangoUsdcTreasury));
        current += 17;
        uint256 expectedDistributeAmount2 = (usdcBalance * 17) / REWARD_RATE_RECIPROCAL;

        vm.warp(current);
        vm.expectEmit(false, false, false, true);
        emit Distribute(expectedDistributeAmount2, 17);

        mangoUsdcTreasury.distribute();

        assertEq(mangoUsdcTreasury.lastDistributedAt(), current);
        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), usdcBalance - expectedDistributeAmount2);
        assertEq(usdcToken.balanceOf(address(mangoStakedToken)), expectedDistributeAmount + expectedDistributeAmount2);

        // distribute after 1000 days
        usdcBalance = usdcToken.balanceOf(address(mangoUsdcTreasury));
        current += 1000 * 1 days;
        uint256 expectedDistributeAmount3 = (usdcBalance * 1000 * 1 days) / REWARD_RATE_RECIPROCAL;

        vm.warp(current);
        vm.expectEmit(false, false, false, true);
        emit Distribute(expectedDistributeAmount3, 1000 * 1 days);
        mangoUsdcTreasury.distribute();

        assertEq(mangoUsdcTreasury.lastDistributedAt(), current);
        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), 0);
        assertEq(
            usdcToken.balanceOf(address(mangoStakedToken)),
            expectedDistributeAmount + expectedDistributeAmount2 + expectedDistributeAmount3
        );
    }

    function testDistributeInSameBlock() public {
        uint256 usdcBalance = 10000 * 10 ** 6;
        usdcToken.transfer(address(mangoUsdcTreasury), usdcBalance);
        uint256 current = TREASURY_REWARD_STARTS_AT + 10;
        vm.warp(current);

        uint256 count = MockStakedToken(address(mangoStakedToken)).supplyCount();
        mangoUsdcTreasury.distribute();
        assertEq(MockStakedToken(address(mangoStakedToken)).supplyCount(), count + 1, "COUNT_0");
        mangoUsdcTreasury.distribute();
        assertEq(MockStakedToken(address(mangoStakedToken)).supplyCount(), count + 1, "COUNT_1");
    }

    function testDistributeWhenDistributableAmountIsZero() public {
        uint256 usdcBalance = 10000 * 10 ** 6;
        usdcToken.transfer(address(mangoUsdcTreasury), usdcBalance);
        uint256 current = TREASURY_REWARD_STARTS_AT + 10;
        vm.warp(current);

        uint256 count = MockStakedToken(address(mangoStakedToken)).supplyCount();
        mangoUsdcTreasury.distribute();
        assertEq(MockStakedToken(address(mangoStakedToken)).supplyCount(), count + 1, "COUNT_0");
        MockStakedToken(address(mangoStakedToken)).setReceiveAmount(0);
        vm.warp(block.timestamp + 100);
        vm.expectEmit(false, false, false, true);
        emit Distribute(0, 100);
        mangoUsdcTreasury.distribute();
        assertEq(MockStakedToken(address(mangoStakedToken)).supplyCount(), count + 2, "COUNT_1");
    }

    function testDistributeWhenStakedTokenReceivesPartially() public {
        uint256 usdcBalance = 10000 * 10 ** 6;
        usdcToken.transfer(address(mangoUsdcTreasury), usdcBalance);
        uint256 current = TREASURY_REWARD_STARTS_AT + 10;
        vm.warp(current);

        assertEq(mangoUsdcTreasury.lastDistributedAt(), TREASURY_REWARD_STARTS_AT);
        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), usdcBalance);
        assertEq(usdcToken.balanceOf(address(mangoStakedToken)), 0);

        uint256 expectedDistributeAmount = (usdcBalance * 10) / REWARD_RATE_RECIPROCAL;

        // Make Situation that staked token cannot receive full tokens
        MockStakedToken(address(mangoStakedToken)).setReceiveAmount(expectedDistributeAmount / 2);
        expectedDistributeAmount /= 2;

        vm.expectEmit(false, false, false, true);
        emit Distribute(expectedDistributeAmount, current - TREASURY_REWARD_STARTS_AT);
        // distribute expectedDistributeAmount
        mangoUsdcTreasury.distribute();

        assertEq(mangoUsdcTreasury.lastDistributedAt(), current);
        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), usdcBalance - expectedDistributeAmount);
        assertEq(usdcToken.balanceOf(address(mangoStakedToken)), expectedDistributeAmount);
    }

    function testDistributeWhenPaused() public {
        mangoUsdcTreasury.pause();
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.PAUSED));
        mangoUsdcTreasury.distribute();
    }

    function testReceiveToken() public {
        uint256 usdcBalance = 10000 * 10 ** 6;
        usdcToken.transfer(address(mangoUsdcTreasury), usdcBalance);
        uint256 current = TREASURY_REWARD_STARTS_AT + 10;
        uint256 amount = 10 * (10 ** 6);
        vm.warp(current);

        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), usdcBalance);
        assertEq(usdcToken.balanceOf(address(mangoStakedToken)), 0);

        uint256 expectedDistributeAmount = (usdcBalance * 10) / REWARD_RATE_RECIPROCAL;
        usdcToken.approve(address(mangoUsdcTreasury), amount);

        vm.expectEmit(false, false, false, true);
        emit Distribute(expectedDistributeAmount, current - TREASURY_REWARD_STARTS_AT);
        mangoUsdcTreasury.receiveToken(amount);

        assertEq(mangoUsdcTreasury.lastDistributedAt(), current);
        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), usdcBalance - expectedDistributeAmount + amount);
        assertEq(usdcToken.balanceOf(address(mangoStakedToken)), expectedDistributeAmount);

        current += 1 days * 1000;

        vm.warp(current);

        usdcToken.approve(address(mangoUsdcTreasury), amount);

        vm.expectEmit(true, false, false, true);
        emit Receive(address(this), amount);
        mangoUsdcTreasury.receiveToken(amount);

        assertEq(mangoUsdcTreasury.lastDistributedAt(), current);
        assertEq(usdcToken.balanceOf(address(mangoUsdcTreasury)), amount);
        assertEq(usdcToken.balanceOf(address(mangoStakedToken)), usdcBalance + amount);
    }

    function testWithdrawLostERC20InvalidAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        mangoUsdcTreasury.withdrawLostERC20(address(usdcToken), address(this));
    }

    function testWithdrawLostERC20() public {
        uint256 lostAmount = 100;
        IERC20 lostToken = new MockToken(lostAmount);
        lostToken.transfer(address(mangoUsdcTreasury), lostAmount);
        assertEq(lostToken.balanceOf(address(mangoUsdcTreasury)), lostAmount);
        mangoUsdcTreasury.withdrawLostERC20(address(lostToken), address(this));
        assertEq(lostToken.balanceOf(address(this)), lostAmount);
    }
}
