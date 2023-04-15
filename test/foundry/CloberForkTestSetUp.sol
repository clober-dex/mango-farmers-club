// SPDX-License-Identifier: MIT

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./Constants.sol";
import "../../contracts/clober/CloberRouter.sol";
import "../../contracts/clober/CloberOrderBook.sol";

pragma solidity ^0.8.0;

/**
 * @dev This is a util contract to run fork test for interactions with CloberOrderBook.
 *
 * For example:
 *
 * ```
 * function setUp() public {
 *     forkTestSetUp = new CloberForkTestSetUp();
 *     (router, orderBook) = forkTestSetUp.run();
 * }
 *
 * ```
 */
contract CloberForkTestSetUp is Test {
    uint256 public constant START_BLOCK_NUMBER = 560792;

    function run() public returns (CloberRouter router, CloberOrderBook orderBook) {
        address runner = msg.sender;
        uint256 testnetFork = vm.createFork(Constants.TESTNET_RPC_URL);
        vm.selectFork(testnetFork);
        vm.rollFork(START_BLOCK_NUMBER);
        assertEq(vm.activeFork(), testnetFork);
        assertEq(block.number, START_BLOCK_NUMBER);

        router = CloberRouter(Constants.MARKET_ROUTER_ADDRESS);
        orderBook = CloberOrderBook(Constants.MANGO_USDC_MARKET_ADDRESS);

        // set balance
        ERC20 mangoToken = ERC20(Constants.MANGO_ADDRESS);
        assertEq(mangoToken.balanceOf(Constants.ADMIN_ADDRESS), Constants.MANGO_TOTAL_SUPPLY);
        ERC20 usdcToken = ERC20(Constants.USDC_ADDRESS);
        assertGt(usdcToken.balanceOf(Constants.ADMIN_ADDRESS), 0);
        assertEq(mangoToken.decimals(), 18);
        assertEq(usdcToken.decimals(), 6);

        vm.startPrank(Constants.ADMIN_ADDRESS);
        mangoToken.transfer(runner, Constants.MANGO_TOTAL_SUPPLY);
        usdcToken.transfer(runner, 10000000 * 10**6);
        vm.stopPrank();

        vm.startPrank(runner);
        mangoToken.approve(Constants.MARKET_ROUTER_ADDRESS, type(uint256).max);
        usdcToken.approve(Constants.MARKET_ROUTER_ADDRESS, type(uint256).max);
        vm.stopPrank();

        assertEq(mangoToken.balanceOf(runner), Constants.MANGO_TOTAL_SUPPLY);
        assertEq(usdcToken.balanceOf(runner), 10000000 * 10**6);
    }
}
