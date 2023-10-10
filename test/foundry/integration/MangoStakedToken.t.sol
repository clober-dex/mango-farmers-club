// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../../contracts/MangoStakedToken.sol";
import "../../../contracts/MangoTreasury.sol";
import "../../mocks/MockUSDC.sol";
import "../../mocks/MockToken.sol";
import "../Constants.sol";

contract MangoStakedTokenIntegrationTest is Test {
    address PROXY_ADMIN = address(0x1231241);
    uint256 constant _BUF = 10 ** 10;

    MockUSDC usdc;
    ERC20 mangoToken;
    MangoStakedToken stakedToken;
    MangoTreasury treasury;
    uint256 startsAt;

    function setUp() public {
        usdc = new MockUSDC(10000000000);
        mangoToken = new MockToken(10000000000 * 10 ** 18);
        startsAt = block.timestamp + 100;
        address stakedTokenLogic = address(new MangoStakedToken(address(mangoToken)));
        stakedToken = MangoStakedToken(
            address(new TransparentUpgradeableProxy(stakedTokenLogic, PROXY_ADMIN, new bytes(0)))
        );
        address treasuryLogic = address(new MangoTreasury(address(stakedToken), address(usdc), address(0)));
        treasury = MangoTreasury(
            address(
                new TransparentUpgradeableProxy(
                    treasuryLogic,
                    PROXY_ADMIN,
                    abi.encodeWithSelector(MangoTreasury.initialize.selector, startsAt)
                )
            )
        );
        stakedToken.initialize(_toArray(address(usdc)), _toArray(address(treasury)));

        usdc.approve(address(treasury), type(uint256).max);
        mangoToken.approve(address(stakedToken), type(uint256).max);
    }

    function _assertApproxLte(uint256 actual, uint256 expected) internal {
        assertApproxEqAbs(actual, expected, 2, "_assertApproxLte");
        assertLe(actual, expected, "_assertApproxLte");
    }

    function _toArray(address a) private pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    function testInitializedStates() public {
        assertEq(treasury.stakedToken(), address(stakedToken), "TREASURY_STAKED_TOKEN");
        assertEq(treasury.receivingToken(), address(usdc), "TREASURY_RECEIVING_TOKEN");
        assertEq(treasury.lastDistributedAt(), startsAt, "TREASURY_LAST_DISTRIBUTED_AT");
        assertEq(treasury.getDistributableAmount(), 0, "TREASURY_DISTRIBUTABLE_AMOUNT");
        assertEq(treasury.owner(), address(this), "TREASURY_OWNER");
        assertEq(treasury.rewardRate(), 0, "TREASURY_REWARD_RATE");

        assertEq(stakedToken.owner(), address(this), "STAKED_TOKEN_OWNER");
        assertEq(stakedToken.totalSupply(), 0, "STAKED_TOKEN_TOTAL_SUPPLY");
        assertEq(stakedToken.name(), "Planted Mango", "STAKED_TOKEN_NAME");
        assertEq(stakedToken.symbol(), "pMANGO", "STAKED_TOKEN_SYMBOL");
        IStakedToken.GlobalRewardSnapshot memory snapshot = stakedToken.globalRewardSnapshot(address(usdc));
        assertEq(snapshot.treasury, address(treasury), "STAKED_TOKEN_TREASURY");
        assertEq(snapshot.rewardPerToken, 0, "STAKED_TOKEN_REWARD_PER_TOKEN");
        assertEq(snapshot.timestamp, block.timestamp, "STAKED_TOKEN_BLOCK_TIMESTAMP");
        assertEq(stakedToken.rewardToken(0), address(usdc), "STAKED_TOKEN_REWARD_TOKEN");
        assertEq(stakedToken.rewardTokens(), _toArray(address(usdc)), "STAKED_TOKEN_REWARD_TOKENS");
        assertEq(stakedToken.rewardTokensLength(), 1, "STAKED_TOKEN_REWARD_TOKENS_LENGTH");
        assertEq(stakedToken.decimals(), 18, "STAKED_TOKEN_DECIMALS");
    }

    function _plantWithBalanceCheck(address to, uint256 amount) internal {
        uint256 beforeMango = mangoToken.balanceOf(address(this));
        uint256 beforeStakedToken = stakedToken.balanceOf(to);
        uint256 beforeTotalSupply = stakedToken.totalSupply();
        stakedToken.plant(amount, to);
        assertEq(stakedToken.balanceOf(to), beforeStakedToken + amount, "PLANT_STAKED_TOKEN_BALANCE");
        assertEq(stakedToken.totalSupply(), beforeTotalSupply + amount, "PLANT_STAKED_TOKEN_TOTAL_SUPPLY");
        assertEq(beforeMango, mangoToken.balanceOf(address(this)) + amount, "PLANT_MANGO_BALANCE");
    }

    function _unplantWithBalanceCheck(address user, uint256 amount) internal {
        uint256 beforeMango = mangoToken.balanceOf(user);
        uint256 beforeStakedToken = stakedToken.balanceOf(user);
        uint256 beforeTotalSupply = stakedToken.totalSupply();
        vm.prank(user);
        stakedToken.unplant(amount, user);
        assertEq(stakedToken.balanceOf(user) + amount, beforeStakedToken, "UNPLANT_STAKED_TOKEN_BALANCE");
        assertEq(stakedToken.totalSupply() + amount, beforeTotalSupply, "UNPLANT_STAKED_TOKEN_TOTAL_SUPPLY");
        assertEq(beforeMango + amount, mangoToken.balanceOf(user), "UNPLANT_MANGO_BALANCE");
    }

    function _harvestWithApproxBalanceCheck(address user, uint256 expectedAmount) internal {
        uint256 beforeUSDC = usdc.balanceOf(user);
        stakedToken.harvest(user);
        _assertApproxLte(usdc.balanceOf(user), beforeUSDC + expectedAmount);
    }

    function _assertEmptyReward(address user) internal {
        _assertApproxReward(user, 0);
    }

    function _assertApproxReward(address user, uint256 amount) internal {
        IStakedToken.HarvestableReward[] memory rewards = stakedToken.harvestableRewards(user);
        assertEq(rewards.length, 1, "rewards.length");
        assertEq(rewards[0].token, address(usdc), "rewards[0].token");
        _assertApproxLte(rewards[0].amount, amount);
    }

    function testWhenTreasuryHasBalanceBeforeStart() public {
        assertLt(block.timestamp, treasury.lastDistributedAt(), "STARTS_AT");
        treasury.receiveToken(10 ** 6);

        // check treasury view functions
        assertEq(usdc.balanceOf(address(treasury)), 10 ** 6, "TREASURY_BALANCE");
        assertEq(treasury.lastDistributedAt(), startsAt, "LAST_DISTRIBUTED_AT");
        assertEq(treasury.getDistributableAmount(), 0, "DISTRIBUTABLE_AMOUNT");

        // plant
        _assertEmptyReward(address(this));
        _plantWithBalanceCheck(address(this), 10 ** 18);
        vm.warp(startsAt - 1);

        // harvest
        _assertEmptyReward(address(this));
        _harvestWithApproxBalanceCheck(address(this), 0);

        // unplant
        _assertEmptyReward(address(this));
        _unplantWithBalanceCheck(address(this), 10 ** 18);

        _assertEmptyReward(address(this));
        assertEq(usdc.balanceOf(address(treasury)), 10 ** 6, "END_TREASURY_BALANCE");
        assertEq(usdc.balanceOf(address(stakedToken)), 0, "END_STAKED_TOKEN_BALANCE");
    }

    function testWhenTreasuryHasBalanceAtStartTime() public {
        assertLt(block.timestamp, treasury.lastDistributedAt(), "STARTS_AT");
        treasury.receiveToken(10 ** 6);

        _plantWithBalanceCheck(address(this), 10 ** 18);
        vm.warp(startsAt);

        // harvest
        _assertEmptyReward(address(this));
        _harvestWithApproxBalanceCheck(address(this), 0);

        // unplant
        _assertEmptyReward(address(this));
        _unplantWithBalanceCheck(address(this), 10 ** 18);

        _assertEmptyReward(address(this));
        assertEq(usdc.balanceOf(address(treasury)), 10 ** 6, "END_TREASURY_BALANCE");
        assertEq(usdc.balanceOf(address(stakedToken)), 0, "END_STAKED_TOKEN_BALANCE");
    }

    function testWhenTreasuryDoesNotHaveBalanceAfterStart() public {
        vm.warp(startsAt + 1000);

        _plantWithBalanceCheck(address(this), 10 ** 18);
        vm.warp(startsAt + 5000);

        _assertEmptyReward(address(this));
        _harvestWithApproxBalanceCheck(address(this), 0);

        _unplantWithBalanceCheck(address(this), 10 ** 18);

        _assertEmptyReward(address(this));
    }

    function testAfterStart() public {
        uint256 initialAmount = 100 * 10 ** 6;
        treasury.receiveToken(initialAmount);
        vm.warp(startsAt + 1000);

        uint256 usdcReward0 = treasury.getDistributableAmount();
        assertEq(usdcReward0, (initialAmount * 1000) / Constants.REWARD_RATE_RECIPROCAL, "DISTRIBUTABLE_0");

        // The first planter will take all rewards
        _plantWithBalanceCheck(Constants.USER_A_ADDRESS, 10 ** 18);
        _assertApproxReward(Constants.USER_A_ADDRESS, usdcReward0);
        // 0 reward at planted block.
        _plantWithBalanceCheck(Constants.USER_B_ADDRESS, 10 ** 18);
        _assertEmptyReward(Constants.USER_B_ADDRESS);

        _harvestWithApproxBalanceCheck(Constants.USER_A_ADDRESS, usdcReward0);
        _harvestWithApproxBalanceCheck(Constants.USER_B_ADDRESS, 0);

        // 0 when harvest again
        _assertEmptyReward(Constants.USER_A_ADDRESS);
        _assertEmptyReward(Constants.USER_B_ADDRESS);
        assertEq(treasury.getDistributableAmount(), 0, "DISTRIBUTABLE_1");
        _harvestWithApproxBalanceCheck(Constants.USER_A_ADDRESS, 0);

        // WARP 1000 sec
        vm.warp(block.timestamp + 1000);
        uint256 usdcReward1 = (usdc.balanceOf(address(treasury)) * 1000) / Constants.REWARD_RATE_RECIPROCAL;
        assertEq(usdcReward1, treasury.getDistributableAmount(), "DISTRIBUTABLE_2");

        _assertApproxReward(Constants.USER_A_ADDRESS, usdcReward1 / 2);
        _assertApproxReward(Constants.USER_B_ADDRESS, usdcReward1 / 2);
        _plantWithBalanceCheck(Constants.USER_A_ADDRESS, 10 ** 18); // A:B = 2:1
        _assertApproxReward(Constants.USER_A_ADDRESS, usdcReward1 / 2);
        _assertApproxReward(Constants.USER_B_ADDRESS, usdcReward1 / 2);

        // WARP 500 sec
        vm.warp(block.timestamp + 500);
        uint256 usdcReward2 = (usdc.balanceOf(address(treasury)) * 500) / Constants.REWARD_RATE_RECIPROCAL;
        assertEq(usdcReward2, treasury.getDistributableAmount(), "DISTRIBUTABLE_3"); // 578
        _assertApproxReward(
            Constants.USER_A_ADDRESS,
            ((usdcReward1 * _BUF) / 2 + ((usdcReward2 * 2) * _BUF) / 3) / _BUF
        );
        _assertApproxReward(Constants.USER_B_ADDRESS, ((usdcReward1 * _BUF) / 2 + (usdcReward2 * _BUF) / 3) / _BUF);
        _unplantWithBalanceCheck(Constants.USER_B_ADDRESS, 10 ** 18); // A:B = 2:0
        _assertApproxReward(
            Constants.USER_A_ADDRESS,
            ((usdcReward1 * _BUF) / 2 + ((usdcReward2 * 2) * _BUF) / 3) / _BUF
        );
        _assertApproxReward(Constants.USER_B_ADDRESS, ((usdcReward1 * _BUF) / 2 + (usdcReward2 * _BUF) / 3) / _BUF);

        vm.warp(block.timestamp + 2000);
        uint256 usdcReward3 = (usdc.balanceOf(address(treasury)) * 2000) / Constants.REWARD_RATE_RECIPROCAL;
        assertEq(usdcReward3, treasury.getDistributableAmount(), "DISTRIBUTABLE_4");
        _assertApproxReward(
            Constants.USER_A_ADDRESS,
            ((usdcReward1 * _BUF) / 2 + ((usdcReward2 * 2) * _BUF) / 3 + usdcReward3 * _BUF) / _BUF
        );
        _assertApproxReward(Constants.USER_B_ADDRESS, ((usdcReward1 * _BUF) / 2 + (usdcReward2 * _BUF) / 3) / _BUF);
        _harvestWithApproxBalanceCheck(
            Constants.USER_B_ADDRESS,
            ((usdcReward1 * _BUF) / 2 + (usdcReward2 * _BUF) / 3) / _BUF
        );
        _assertApproxReward(
            Constants.USER_A_ADDRESS,
            ((usdcReward1 * _BUF) / 2 + ((usdcReward2 * 2) * _BUF) / 3 + usdcReward3 * _BUF) / _BUF
        );
        _assertEmptyReward(Constants.USER_B_ADDRESS);
        _plantWithBalanceCheck(Constants.USER_B_ADDRESS, 10 ** 18); // A:B = 2:1

        vm.warp(block.timestamp + 1000);
        uint256 currentTreasuryBalance = usdc.balanceOf(address(treasury));
        uint256 usdcReward4 = (currentTreasuryBalance * 1000) / Constants.REWARD_RATE_RECIPROCAL;
        assertEq(usdcReward4, treasury.getDistributableAmount(), "DISTRIBUTABLE_5");
        treasury.receiveToken(initialAmount); // Not affect the rewards at the same block

        _assertApproxReward(
            Constants.USER_A_ADDRESS,
            ((usdcReward1 * _BUF) /
                2 +
                ((usdcReward2 * 2) * _BUF) /
                3 +
                usdcReward3 *
                _BUF +
                ((usdcReward4 * 2) * _BUF) /
                3) / _BUF
        );
        _assertApproxReward(Constants.USER_B_ADDRESS, usdcReward4 / 3);
        _harvestWithApproxBalanceCheck(Constants.USER_B_ADDRESS, usdcReward4 / 3);
        _assertApproxReward(
            Constants.USER_A_ADDRESS,
            ((usdcReward1 * _BUF) /
                2 +
                ((usdcReward2 * 2) * _BUF) /
                3 +
                usdcReward3 *
                _BUF +
                ((usdcReward4 * 2) * _BUF) /
                3) / _BUF
        );
        _assertEmptyReward(Constants.USER_B_ADDRESS);

        _harvestWithApproxBalanceCheck(
            Constants.USER_A_ADDRESS,
            ((usdcReward1 * _BUF) /
                2 +
                ((usdcReward2 * 2) * _BUF) /
                3 +
                usdcReward3 *
                _BUF +
                ((usdcReward4 * 2) * _BUF) /
                3) / _BUF
        );
        _unplantWithBalanceCheck(Constants.USER_A_ADDRESS, 2 * 10 ** 18); // A:B = 0:1

        // treasury usdc balance check
        assertEq(usdc.balanceOf(address(treasury)), currentTreasuryBalance - usdcReward4 + initialAmount);

        vm.warp(block.timestamp + 3000);
        currentTreasuryBalance = usdc.balanceOf(address(treasury));
        uint256 usdcReward5 = (currentTreasuryBalance * 3000) / Constants.REWARD_RATE_RECIPROCAL;
        assertEq(usdcReward5, treasury.getDistributableAmount(), "DISTRIBUTABLE_6");

        _assertEmptyReward(Constants.USER_A_ADDRESS);
        _assertApproxReward(Constants.USER_B_ADDRESS, usdcReward5);

        _harvestWithApproxBalanceCheck(Constants.USER_B_ADDRESS, usdcReward5);
        _assertEmptyReward(Constants.USER_B_ADDRESS);
    }
}
