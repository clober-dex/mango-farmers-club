// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../contracts/MangoStakedToken.sol";
import "../../../contracts/interfaces/ITreasury.sol";
import "../../../contracts/Errors.sol";
import "../../mocks/MockToken.sol";
import "../../mocks/MockUSDC.sol";
import "../../mocks/MockTreasury.sol";

contract MangoStakedTokenUnitTest is Test {
    uint256 public constant INITIAL_MANGO_SUPPLY = 1_000_000_000 * (10**18);
    uint256 public constant INITIAL_USDC_SUPPLY = 1_000_000_000 * (10**6);
    uint256 public constant TREASURY_REWARD_STARTS_AT = 100;
    uint256 public constant INITIAL_BLOCK_TIMESTAMP = 10;
    address constant PROXY_ADMIN = address(0x1231241);

    IERC20 mangoToken;
    IERC20 usdcToken;
    MangoStakedToken mangoStakedToken;
    ITreasury usdcTreasury;
    ITreasury mangoTreasury;

    function setUp() public {
        vm.warp(INITIAL_BLOCK_TIMESTAMP);
        mangoToken = new MockToken(INITIAL_MANGO_SUPPLY);
        usdcToken = new MockUSDC(INITIAL_USDC_SUPPLY);
        address mangoStakedTokenLogic = address(new MangoStakedToken(address(mangoToken)));
        mangoStakedToken = MangoStakedToken(
            address(new TransparentUpgradeableProxy(mangoStakedTokenLogic, PROXY_ADMIN, new bytes(0)))
        );
        usdcTreasury = new MockTreasury(address(mangoStakedToken), address(usdcToken), TREASURY_REWARD_STARTS_AT);
        mangoTreasury = new MockTreasury(address(mangoStakedToken), address(mangoToken), TREASURY_REWARD_STARTS_AT);

        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(usdcToken);
        rewardTokens[1] = address(mangoToken);
        address[] memory treasuries = new address[](2);
        treasuries[0] = address(usdcTreasury);
        treasuries[1] = address(mangoTreasury);

        mangoStakedToken.initialize(rewardTokens, treasuries);

        usdcToken.transfer(address(usdcTreasury), INITIAL_USDC_SUPPLY);
        mangoToken.transfer(address(mangoTreasury), INITIAL_MANGO_SUPPLY / 2);
    }

    function testInitialize() public {
        MangoStakedToken newMangoStakedToken = new MangoStakedToken(address(mangoToken));
        address[] memory rewardTokens = new address[](1);
        rewardTokens[0] = address(usdcToken);
        address[] memory treasuries = new address[](1);
        treasuries[0] = address(usdcTreasury);

        newMangoStakedToken.initialize(rewardTokens, treasuries);
    }

    function testName() public {
        assertEq(mangoStakedToken.name(), "Planted Mango");
    }

    function testSymbol() public {
        assertEq(mangoStakedToken.symbol(), "pMANGO");
    }

    function testTransfer(uint256 amount) public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.ACCESS));
        mangoStakedToken.transfer(address(1), amount);
    }

    function testRewardToken() public {
        assertEq(mangoStakedToken.rewardToken(0), address(usdcToken));
    }

    function testRewardTokens() public {
        address[] memory rewardTokens = mangoStakedToken.rewardTokens();
        assertEq(rewardTokens.length, 2);
        assertEq(rewardTokens[0], address(usdcToken));
    }

    function testRewardTokensLength() public {
        assertEq(mangoStakedToken.rewardTokensLength(), 2);
    }

    function testGlobalRewardSnapshot() public {
        IStakedToken.GlobalRewardSnapshot memory snapshot = mangoStakedToken.globalRewardSnapshot(address(usdcToken));
        assertEq(snapshot.timestamp, INITIAL_BLOCK_TIMESTAMP);
        assertEq(snapshot.rewardPerToken, 0);
    }

    function testUserRewardSnapshot() public {
        IStakedToken.UserRewardSnapshot memory snapshot = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(usdcToken)
        );
        assertEq(snapshot.rewardPerToken, 0);
        assertEq(snapshot.harvestableReward, 0);
    }

    function testHarvestableRewards() public {
        uint256 amount = 5 * (10**18);
        uint256 stage1Timestamp = TREASURY_REWARD_STARTS_AT + 10;
        uint256 stage2Timestamp = TREASURY_REWARD_STARTS_AT + 20;
        uint256 expectedReward1 = (stage1Timestamp - TREASURY_REWARD_STARTS_AT) * (10**6);
        uint256 expectedReward2 = (stage2Timestamp - TREASURY_REWARD_STARTS_AT) * (10**6);

        vm.warp(stage1Timestamp);

        IStakedToken.HarvestableReward[] memory rewards = mangoStakedToken.harvestableRewards(address(this));
        IStakedToken.HarvestableReward memory reward = rewards[0];
        assertEq(reward.token, address(usdcToken));
        assertEq(reward.amount, 0);

        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));

        rewards = mangoStakedToken.harvestableRewards(address(this));
        reward = rewards[0];
        assertEq(reward.token, address(usdcToken));
        assertEq(reward.amount, expectedReward1);

        vm.warp(stage2Timestamp);
        rewards = mangoStakedToken.harvestableRewards(address(this));
        reward = rewards[0];
        assertEq(reward.token, address(usdcToken));
        assertEq(reward.amount, expectedReward2);
    }

    function testPlant() public {
        uint256 initialBalance = mangoToken.balanceOf(address(this));
        uint256 amount = 5 * (10**18);
        uint256 stage1Timestamp = TREASURY_REWARD_STARTS_AT + 10;
        uint256 stage2Timestamp = TREASURY_REWARD_STARTS_AT + 20;
        uint256 expectedRewardUsdc = (stage2Timestamp - TREASURY_REWARD_STARTS_AT) * (10**6);
        uint256 expectedRewardMango = (stage2Timestamp - TREASURY_REWARD_STARTS_AT) * (10**18);

        vm.warp(stage1Timestamp);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));
        assertEq(mangoToken.balanceOf(address(this)), initialBalance - amount);

        vm.warp(stage2Timestamp);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));
        assertEq(mangoToken.balanceOf(address(this)), initialBalance - 2 * amount);

        IStakedToken.UserRewardSnapshot memory snapshot = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(usdcToken)
        );
        assertEq(snapshot.rewardPerToken, expectedRewardUsdc / 5);
        assertEq(snapshot.harvestableReward, expectedRewardUsdc);

        IStakedToken.UserRewardSnapshot memory snapshot2 = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(mangoToken)
        );
        assertEq(snapshot2.rewardPerToken, expectedRewardMango / 5);
        assertEq(snapshot2.harvestableReward, expectedRewardMango);
    }

    function testPlantWhenPaused() public {
        uint256 amount = 5 * (10**18);

        vm.warp(TREASURY_REWARD_STARTS_AT + 10);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.pause();
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.PAUSED));
        mangoStakedToken.plant(amount, address(this));
    }

    function testPlantAndHarvest() public {
        uint256 initialBalance = mangoToken.balanceOf(address(this));
        uint256 amount = 5 * (10**18);
        uint256 stage1Timestamp = TREASURY_REWARD_STARTS_AT + 10;
        uint256 expectedRewardUsdc = (stage1Timestamp - TREASURY_REWARD_STARTS_AT) * (10**6);
        uint256 expectedRewardMango = (stage1Timestamp - TREASURY_REWARD_STARTS_AT) * (10**18);

        vm.warp(stage1Timestamp);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));
        assertEq(mangoToken.balanceOf(address(this)), initialBalance - amount);

        mangoStakedToken.harvest(address(this));

        assertEq(usdcToken.balanceOf(address(this)), expectedRewardUsdc);
        assertEq(mangoToken.balanceOf(address(this)), initialBalance - amount + expectedRewardMango);

        IStakedToken.UserRewardSnapshot memory snapshot = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(usdcToken)
        );
        assertEq(snapshot.rewardPerToken, expectedRewardUsdc / 5);
        assertEq(snapshot.harvestableReward, 0);

        IStakedToken.UserRewardSnapshot memory snapshot2 = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(mangoToken)
        );
        assertEq(snapshot2.rewardPerToken, expectedRewardMango / 5);
        assertEq(snapshot2.harvestableReward, 0);
    }

    function testUnplant() public {
        uint256 initialBalance = mangoToken.balanceOf(address(this));
        uint256 amount = 5 * (10**18);
        uint256 stage1Timestamp = TREASURY_REWARD_STARTS_AT + 10;
        uint256 stage2Timestamp = TREASURY_REWARD_STARTS_AT + 20;
        uint256 expectedRewardUsdc = (stage2Timestamp - TREASURY_REWARD_STARTS_AT) * (10**6);
        uint256 expectedRewardMango = (stage2Timestamp - TREASURY_REWARD_STARTS_AT) * (10**18);

        vm.warp(stage1Timestamp);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));
        assertEq(mangoToken.balanceOf(address(this)), initialBalance - amount);

        vm.warp(stage2Timestamp);
        mangoStakedToken.unplant(amount, address(this));
        assertEq(mangoToken.balanceOf(address(this)), initialBalance);

        IStakedToken.UserRewardSnapshot memory snapshot = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(usdcToken)
        );
        assertEq(snapshot.rewardPerToken, expectedRewardUsdc / 5);
        assertEq(snapshot.harvestableReward, expectedRewardUsdc);

        IStakedToken.UserRewardSnapshot memory snapshot2 = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(mangoToken)
        );
        assertEq(snapshot2.rewardPerToken, expectedRewardMango / 5);
        assertEq(snapshot2.harvestableReward, expectedRewardMango);
    }

    function testUnplantWhenPaused() public {
        uint256 amount = 5 * (10**18);

        vm.warp(TREASURY_REWARD_STARTS_AT + 10);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));

        mangoStakedToken.pause();
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.PAUSED));
        mangoStakedToken.unplant(amount, address(this));
    }

    function testHarvest() public {
        uint256 amount = 5 * (10**18);
        uint256 stage1Timestamp = TREASURY_REWARD_STARTS_AT + 10;
        uint256 stage2Timestamp = TREASURY_REWARD_STARTS_AT + 20;
        uint256 expectedReward = (stage2Timestamp - TREASURY_REWARD_STARTS_AT) * (10**6);

        uint256 stage3Timestamp = TREASURY_REWARD_STARTS_AT + 30;
        uint256 expectedReward2 = ((stage3Timestamp - stage2Timestamp) * (10**6)) / 2;

        // stage1
        vm.warp(stage1Timestamp);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));

        IStakedToken.UserRewardSnapshot memory snapshot = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(usdcToken)
        );
        assertEq(snapshot.rewardPerToken, 0);
        assertEq(snapshot.harvestableReward, 0);

        // stage2
        vm.warp(stage2Timestamp);
        assertEq(usdcToken.balanceOf(address(this)), 0);
        mangoStakedToken.harvest(address(this));

        snapshot = mangoStakedToken.userRewardSnapshot(address(this), address(usdcToken));
        assertEq(snapshot.rewardPerToken, expectedReward / 5);
        assertEq(snapshot.harvestableReward, 0);

        assertEq(usdcToken.balanceOf(address(this)), expectedReward);

        uint256 userAddressSourceUint = 1;
        address user = address(bytes20(keccak256(abi.encodePacked(userAddressSourceUint))));
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(user));

        snapshot = mangoStakedToken.userRewardSnapshot(address(user), address(usdcToken));
        assertEq(snapshot.rewardPerToken, expectedReward / 5);
        assertEq(snapshot.harvestableReward, 0);

        // stage3
        vm.warp(stage3Timestamp);
        assertEq(usdcToken.balanceOf(address(this)), expectedReward);
        assertEq(usdcToken.balanceOf(address(user)), 0);
        mangoStakedToken.harvest(address(this));
        mangoStakedToken.harvest(address(user));

        snapshot = mangoStakedToken.userRewardSnapshot(address(user), address(usdcToken));
        assertEq(snapshot.rewardPerToken, expectedReward / 5 + expectedReward2 / 5);
        assertEq(snapshot.harvestableReward, 0);

        assertEq(usdcToken.balanceOf(address(this)), expectedReward + expectedReward2);
        assertEq(usdcToken.balanceOf(address(user)), expectedReward2);
    }

    function testHarvestWhenPaused() public {
        uint256 amount = 5 * (10**18);

        vm.warp(TREASURY_REWARD_STARTS_AT + 10);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));

        mangoStakedToken.pause();
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.PAUSED));
        mangoStakedToken.harvest(address(this));
    }

    function testHarvestFloorReward() public {
        uint256 amount = 5 * (10**18);
        uint256 amountByOtherUser = 3 * (10**18);
        uint256 stage1Timestamp = TREASURY_REWARD_STARTS_AT + 10;
        uint256 stage2Timestamp = TREASURY_REWARD_STARTS_AT + 27;
        uint256 expectedTotalReward = (stage2Timestamp - TREASURY_REWARD_STARTS_AT) * (10**6);

        uint256 stage3Timestamp = TREASURY_REWARD_STARTS_AT + 42;
        uint256 expectedTotalReward2 = ((stage3Timestamp - stage2Timestamp) * (10**6));

        // stage1
        vm.warp(stage1Timestamp);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));

        IStakedToken.UserRewardSnapshot memory snapshot = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(usdcToken)
        );
        assertEq(snapshot.rewardPerToken, 0);
        assertEq(snapshot.harvestableReward, 0);

        // stage2
        vm.warp(stage2Timestamp);
        assertEq(usdcToken.balanceOf(address(this)), 0);
        mangoStakedToken.harvest(address(this));

        snapshot = mangoStakedToken.userRewardSnapshot(address(this), address(usdcToken));
        assertEq(snapshot.rewardPerToken, expectedTotalReward / 5);
        assertEq(snapshot.harvestableReward, 0);

        assertEq(usdcToken.balanceOf(address(this)), (expectedTotalReward / 5) * 5);

        uint256 userAddressSourceUint = 1;
        address user = address(bytes20(keccak256(abi.encodePacked(userAddressSourceUint))));
        mangoToken.approve(address(mangoStakedToken), amountByOtherUser);
        mangoStakedToken.plant(amountByOtherUser, address(user));

        snapshot = mangoStakedToken.userRewardSnapshot(address(user), address(usdcToken));
        assertEq(snapshot.rewardPerToken, expectedTotalReward / 5);
        assertEq(snapshot.harvestableReward, 0);

        // stage3
        vm.warp(stage3Timestamp);

        mangoStakedToken.harvest(address(this));
        mangoStakedToken.harvest(address(user));

        snapshot = mangoStakedToken.userRewardSnapshot(address(user), address(usdcToken));
        assertEq(snapshot.rewardPerToken, expectedTotalReward / 5 + expectedTotalReward2 / 8);
        assertEq(snapshot.harvestableReward, 0);

        assertEq(
            usdcToken.balanceOf(address(this)),
            ((expectedTotalReward / 5) * 5) + ((expectedTotalReward2 / 8) * 5)
        );
        assertEq(usdcToken.balanceOf(address(user)), ((expectedTotalReward2 / 8) * 3));
    }

    function testPlantUnplantHarvest() public {
        uint256 amount = 5 * (10**18);
        uint256 amountByOtherUser = 3 * (10**18);
        uint256 stage1Timestamp = TREASURY_REWARD_STARTS_AT + 10;
        uint256 stage2Timestamp = TREASURY_REWARD_STARTS_AT + 27;
        uint256 expectedTotalReward = (stage2Timestamp - TREASURY_REWARD_STARTS_AT) * (10**6);

        uint256 stage3Timestamp = TREASURY_REWARD_STARTS_AT + 42;
        uint256 expectedTotalReward2 = ((stage3Timestamp - stage2Timestamp) * (10**6));

        uint256 stage4Timestamp = TREASURY_REWARD_STARTS_AT + 57;
        uint256 expectedTotalReward3 = ((stage4Timestamp - stage3Timestamp) * (10**6));

        // stage1
        vm.warp(stage1Timestamp);
        mangoToken.approve(address(mangoStakedToken), amount);
        mangoStakedToken.plant(amount, address(this));

        IStakedToken.UserRewardSnapshot memory snapshot = mangoStakedToken.userRewardSnapshot(
            address(this),
            address(usdcToken)
        );
        assertEq(snapshot.rewardPerToken, 0);
        assertEq(snapshot.harvestableReward, 0);

        // stage2
        vm.warp(stage2Timestamp);
        assertEq(usdcToken.balanceOf(address(this)), 0);
        mangoStakedToken.unplant(10**18, address(this));

        snapshot = mangoStakedToken.userRewardSnapshot(address(this), address(usdcToken));
        assertEq(snapshot.rewardPerToken, expectedTotalReward / 5);
        assertEq(snapshot.harvestableReward, (expectedTotalReward / 5) * 5);

        // stage3
        vm.warp(stage3Timestamp);
        uint256 userAddressSourceUint = 1;
        address user = address(bytes20(keccak256(abi.encodePacked(userAddressSourceUint))));
        mangoToken.approve(address(mangoStakedToken), amountByOtherUser);
        mangoStakedToken.plant(amountByOtherUser, address(user));

        snapshot = mangoStakedToken.userRewardSnapshot(address(user), address(usdcToken));
        assertEq(snapshot.rewardPerToken, expectedTotalReward / 5 + expectedTotalReward2 / 4);
        assertEq(snapshot.harvestableReward, 0);

        // stage4
        vm.warp(stage4Timestamp);
        mangoStakedToken.harvest(address(this));
        mangoStakedToken.harvest(address(user));

        snapshot = mangoStakedToken.userRewardSnapshot(address(user), address(usdcToken));
        assertEq(
            snapshot.rewardPerToken,
            expectedTotalReward / 5 + expectedTotalReward2 / 4 + expectedTotalReward3 / 7
        );
        assertEq(snapshot.harvestableReward, 0);

        assertEq(
            usdcToken.balanceOf(address(this)),
            (expectedTotalReward / 5) * 5 + (expectedTotalReward2 / 4 + expectedTotalReward3 / 7) * 4
        );
        assertEq(usdcToken.balanceOf(address(user)), ((expectedTotalReward3 / 7) * 3));
    }

    function testSupplyRewardEmptyInput() public {
        // should be returned
        vm.prank(address(usdcTreasury));
        mangoStakedToken.supplyReward(address(usdcToken), 0);
    }

    function testSupplyRewardAccess() public {
        vm.prank(address(1));
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.ACCESS));
        mangoStakedToken.supplyReward(address(usdcToken), 0);
    }

    function testSupplyRewardWhenTotalStakedAmountZero() public {
        // should returned
        vm.prank(address(usdcTreasury));
        mangoStakedToken.supplyReward(address(usdcToken), 1);
    }

    function testAddRewardToken() public {
        IERC20 newToken = new MockToken(10**18);
        address newTreasury = address(
            new MockTreasury(address(mangoStakedToken), address(newToken), TREASURY_REWARD_STARTS_AT)
        );
        uint256 rewardTokensLength = mangoStakedToken.rewardTokensLength();
        mangoStakedToken.addRewardToken(address(newToken), newTreasury);
        assertEq(mangoStakedToken.rewardTokensLength(), rewardTokensLength + 1, "REWARD_TOKENS_LENGTH");
        assertEq(mangoStakedToken.rewardToken(rewardTokensLength), address(newToken), "REWARD_TOKEN");
        IStakedToken.GlobalRewardSnapshot memory snapshot = mangoStakedToken.globalRewardSnapshot(address(newToken));
        assertEq(snapshot.rewardPerToken, 0, "REWARD_PER_TOKEN");
        assertEq(snapshot.treasury, newTreasury, "TREASURY");
        assertEq(snapshot.timestamp, block.timestamp, "BLOCK_TIMESTAMP");
    }

    function testAddRewardTokenAccess() public {
        IERC20 newToken = new MockToken(10**18);
        address newTreasury = address(
            new MockTreasury(address(mangoStakedToken), address(newToken), TREASURY_REWARD_STARTS_AT)
        );
        vm.prank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        mangoStakedToken.addRewardToken(address(newToken), newTreasury);
    }

    function testAddRewardTokenAlreadyRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.ACCESS));
        mangoStakedToken.addRewardToken(address(usdcToken), address(usdcTreasury));
    }

    function testAddRewardTokenInvalidTreasury() public {
        IERC20 newToken = new MockToken(10**18);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        mangoStakedToken.addRewardToken(address(newToken), address(usdcTreasury));
    }

    function testWithdrawLostERC20UnderlyingToken() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        mangoStakedToken.withdrawLostERC20(address(mangoToken), address(this));
    }

    function testWithdrawLostERC20RewardToken() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        mangoStakedToken.withdrawLostERC20(address(usdcToken), address(this));
    }

    function testWithdrawLostERC20() public {
        uint256 lostAmount = 100;
        IERC20 lostToken = new MockToken(lostAmount);
        lostToken.transfer(address(mangoStakedToken), lostAmount);
        assertEq(lostToken.balanceOf(address(mangoStakedToken)), lostAmount);
        mangoStakedToken.withdrawLostERC20(address(lostToken), address(this));
        assertEq(lostToken.balanceOf(address(this)), lostAmount);
    }
}
