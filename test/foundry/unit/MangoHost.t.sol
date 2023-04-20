// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../../mocks/MockUSDC.sol";
import "../../mocks/MockToken.sol";
import "../../mocks/MockTokenReceiver.sol";
import "../../../contracts/MangoHost.sol";
import "../../../contracts/Errors.sol";

contract MangoHostUnitTest is Test {
    event SetTokenReceiver(address indexed token, address indexed receiver);

    uint256 public constant INITIAL_USDC_SUPPLY = 1_000_000_000 * (10 ** 6);
    address constant PROXY_ADMIN = address(0x1231241);

    IERC20 usdcToken;
    IERC20 usdc2Token;
    address mangoHostLogic;
    MangoHost mangoHost;

    function setUp() public {
        usdcToken = new MockUSDC(INITIAL_USDC_SUPPLY);
        usdc2Token = new MockUSDC(INITIAL_USDC_SUPPLY);

        ITokenReceiver[] memory receivers = new ITokenReceiver[](2);
        receivers[0] = new MockTokenReceiver(address(usdcToken));
        receivers[1] = new MockTokenReceiver(address(usdc2Token));

        mangoHostLogic = address(new MangoHost());
        mangoHost = MangoHost(
            address(
                new TransparentUpgradeableProxy(
                    mangoHostLogic,
                    PROXY_ADMIN,
                    abi.encodeWithSelector(MangoHost.initialize.selector, receivers)
                )
            )
        );
    }

    function testInitialize() public {
        MangoHost newMangoHost = MangoHost(
            address(new TransparentUpgradeableProxy(mangoHostLogic, PROXY_ADMIN, new bytes(0)))
        );

        ITokenReceiver[] memory receivers = new ITokenReceiver[](1);
        receivers[0] = new MockTokenReceiver(address(usdcToken));
        assertEq(newMangoHost.owner(), address(0), "BEFORE_OWNER");
        assertEq(usdcToken.allowance(address(newMangoHost), address(receivers[0])), 0, "BEFORE_ALLOWANCE");
        address initializer = address(0x1111);
        vm.prank(initializer);
        newMangoHost.initialize(receivers);
        assertEq(newMangoHost.owner(), initializer, "AFTER_OWNER");
        assertEq(
            usdcToken.allowance(address(newMangoHost), address(receivers[0])),
            type(uint256).max,
            "AFTER_ALLOWANCE"
        );
    }

    function testInitializeTwice() public {
        ITokenReceiver[] memory receivers = new ITokenReceiver[](1);
        receivers[0] = new MockTokenReceiver(address(usdcToken));
        vm.expectRevert("Initializable: contract is already initialized");
        mangoHost.initialize(receivers);
    }

    function testSetApprovalsUnregisteredToken() public {
        IERC20 newToken = new MockUSDC(INITIAL_USDC_SUPPLY);

        assertEq(
            newToken.allowance(address(mangoHost), address(mangoHost.tokenReceiver(address(newToken)))),
            0,
            "BEFORE"
        );

        mangoHost.setApprovals(address(newToken));

        assertEq(
            newToken.allowance(address(mangoHost), address(mangoHost.tokenReceiver(address(newToken)))),
            0,
            "AFTER"
        );
    }

    function testSetApprovals() public {
        address receiver = mangoHost.tokenReceiver(address(usdcToken));
        vm.prank(address(mangoHost));
        usdcToken.approve(receiver, 1);
        assertEq(usdcToken.allowance(address(mangoHost), receiver), 1, "BEFORE");

        mangoHost.setApprovals(address(usdcToken));

        assertEq(usdcToken.allowance(address(mangoHost), receiver), type(uint256).max, "AFTER");
    }

    function testDistributeZeroAmount() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdcToken);
        uint256 callCount = MockTokenReceiver(address(mangoHost.tokenReceiver(address(usdcToken)))).callCount();
        mangoHost.distributeTokens(tokens);
        assertEq(MockTokenReceiver(address(mangoHost.tokenReceiver(address(usdcToken)))).callCount(), callCount);
    }

    function testDistributeTokensTwoValidToken() public {
        uint256 amount = 1000 * (10 ** 6);
        usdcToken.transfer(address(mangoHost), amount);
        usdc2Token.transfer(address(mangoHost), amount);

        address[] memory tokenList = new address[](2);
        tokenList[0] = address(usdcToken);
        tokenList[1] = address(usdc2Token);

        assertEq(usdcToken.balanceOf(address(mangoHost)), amount);
        assertEq(usdcToken.balanceOf(address(mangoHost.tokenReceiver(address(usdcToken)))), 0);
        assertEq(usdc2Token.balanceOf(address(mangoHost)), amount);
        assertEq(usdc2Token.balanceOf(address(mangoHost.tokenReceiver(address(usdc2Token)))), 0);

        mangoHost.distributeTokens(tokenList);

        assertEq(usdcToken.balanceOf(address(mangoHost)), 0);
        assertEq(usdcToken.balanceOf(address(mangoHost.tokenReceiver(address(usdcToken)))), amount);
        assertEq(usdc2Token.balanceOf(address(mangoHost)), 0);
        assertEq(usdc2Token.balanceOf(address(mangoHost.tokenReceiver(address(usdc2Token)))), amount);
    }

    function testDistributeTokensEmptyList() public {
        uint256 amount = 1000 * (10 ** 6);
        usdcToken.transfer(address(mangoHost), amount);

        address[] memory tokenList = new address[](0);

        assertEq(usdcToken.balanceOf(address(mangoHost)), amount);
        assertEq(usdcToken.balanceOf(address(mangoHost.tokenReceiver(address(usdcToken)))), 0);

        mangoHost.distributeTokens(tokenList);

        assertEq(usdcToken.balanceOf(address(mangoHost)), amount);
        assertEq(usdcToken.balanceOf(address(mangoHost.tokenReceiver(address(usdcToken)))), 0);
    }

    function testDistributeTokensWithOneZeroBalanceToken() public {
        uint256 amount = 1000 * (10 ** 6);
        usdcToken.transfer(address(mangoHost), amount);

        address[] memory tokenList = new address[](2);
        tokenList[0] = address(usdcToken);
        tokenList[1] = address(usdc2Token);

        assertEq(usdcToken.balanceOf(address(mangoHost)), amount);
        assertEq(usdcToken.balanceOf(address(mangoHost.tokenReceiver(address(usdcToken)))), 0);
        assertEq(usdc2Token.balanceOf(address(mangoHost)), 0);
        assertEq(usdc2Token.balanceOf(address(mangoHost.tokenReceiver(address(usdc2Token)))), 0);

        mangoHost.distributeTokens(tokenList);

        assertEq(usdcToken.balanceOf(address(mangoHost)), 0);
        assertEq(usdcToken.balanceOf(address(mangoHost.tokenReceiver(address(usdcToken)))), amount);
        assertEq(usdc2Token.balanceOf(address(mangoHost)), 0);
        assertEq(usdc2Token.balanceOf(address(mangoHost.tokenReceiver(address(usdc2Token)))), 0);
    }

    function testDistributeTokensWithOneInvalidToken() public {
        uint256 amount = 1000 * (10 ** 6);
        usdcToken.transfer(address(mangoHost), amount);

        address[] memory tokenList = new address[](2);
        tokenList[0] = address(usdcToken);
        tokenList[1] = address(1);

        assertEq(usdcToken.balanceOf(address(mangoHost)), amount);
        assertEq(usdcToken.balanceOf(address(mangoHost.tokenReceiver(address(usdcToken)))), 0);

        mangoHost.distributeTokens(tokenList);

        assertEq(usdcToken.balanceOf(address(mangoHost)), 0);
        assertEq(usdcToken.balanceOf(address(mangoHost.tokenReceiver(address(usdcToken)))), amount);
    }

    function testSetTokenReceiver() public {
        MockTokenReceiver oldReceiver = MockTokenReceiver(mangoHost.tokenReceiver(address(usdcToken)));
        MockTokenReceiver newReceiver = new MockTokenReceiver(address(usdcToken));

        assertEq(usdcToken.allowance(address(mangoHost), address(oldReceiver)), type(uint256).max);
        assertEq(usdcToken.allowance(address(mangoHost), address(newReceiver)), 0);

        vm.expectEmit(true, true, false, false);
        emit SetTokenReceiver(address(usdcToken), address(newReceiver));
        mangoHost.setTokenReceiver(newReceiver);

        assertEq(usdcToken.allowance(address(mangoHost), address(oldReceiver)), 0);
        assertEq(usdcToken.allowance(address(mangoHost), address(newReceiver)), type(uint256).max);

        assertEq(address(mangoHost.tokenReceiver(address(usdcToken))), address(newReceiver));
    }

    function testSetTokenReceiverAccess() public {
        MockTokenReceiver newReceiver = new MockTokenReceiver(address(usdcToken));
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        mangoHost.setTokenReceiver(newReceiver);
    }

    function testSetNewTokenReceiver() public {
        IERC20 newToken = new MockToken(42);
        MockTokenReceiver newReceiver = new MockTokenReceiver(address(newToken));

        assertEq(newToken.allowance(address(mangoHost), address(newReceiver)), 0);

        vm.expectEmit(true, true, false, false);
        emit SetTokenReceiver(address(newToken), address(newReceiver));
        mangoHost.setTokenReceiver(newReceiver);
        assertEq(address(mangoHost.tokenReceiver(address(newToken))), address(newReceiver));

        assertEq(newToken.allowance(address(mangoHost), address(newReceiver)), type(uint256).max);
    }

    function testWithdrawLostERC20Access() public {
        IERC20 lostToken = new MockToken(10000);
        lostToken.transfer(address(mangoHost), 10000);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        mangoHost.withdrawLostERC20(address(lostToken), address(this));
    }

    function testWithdrawLostERC20InvalidAddress() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_ADDRESS));
        mangoHost.withdrawLostERC20(address(usdcToken), address(this));
    }

    function testWithdrawLostERC20() public {
        uint256 lostAmount = 100;
        IERC20 lostToken = new MockToken(lostAmount);
        lostToken.transfer(address(mangoHost), lostAmount);
        assertEq(lostToken.balanceOf(address(mangoHost)), lostAmount);
        mangoHost.withdrawLostERC20(address(lostToken), address(this));
        assertEq(lostToken.balanceOf(address(this)), lostAmount);
    }
}
