// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../mocks/MockToken.sol";
import "../../mocks/MockUSDC.sol";
import "../../mocks/MockTokenReceiver.sol";
import "../../../contracts/interfaces/ITokenReceiver.sol";
import "../../../contracts/MangoPublicRegistration.sol";
import "../../../contracts/Errors.sol";

contract MangoPublicRegistrationUnitTest is Test {
    uint256 public constant INITIAL_MANGO_SUPPLY = 4_500_000_000 * 10 ** 18;
    uint256 public constant INITIAL_USDC_SUPPLY = 800_000 * (10 ** 6);
    uint256 private constant _MANGO_ALLOCATION_AMOUNT = 4_500_000_000 * 10 ** 18; // 4.5 billion MANGO tokens
    uint256 private constant _USDC_HARDCAP = 400_000 * 10 ** 6; // 400,000 USDC

    address constant PROXY_ADMIN = address(0x1231241);

    IERC20 mangoToken;
    IERC20 usdcToken;
    ITokenReceiver usdcReceiver;
    address mangoPublicRegistrationLogic;
    MangoPublicRegistration mangoPublicRegistration;

    function setUp() public {
        mangoToken = new MockToken(INITIAL_MANGO_SUPPLY);
        usdcToken = new MockUSDC(INITIAL_USDC_SUPPLY);
        usdcReceiver = new MockTokenReceiver(address(usdcToken));
        mangoPublicRegistrationLogic = address(
            new MangoPublicRegistration(50, address(mangoToken), address(usdcToken))
        );
        mangoPublicRegistration = MangoPublicRegistration(
            address(
                new TransparentUpgradeableProxy(
                    mangoPublicRegistrationLogic,
                    PROXY_ADMIN,
                    abi.encodeWithSelector(MangoPublicRegistration.initialize.selector)
                )
            )
        );
        mangoToken.transfer(address(mangoPublicRegistration), INITIAL_MANGO_SUPPLY);
    }

    function _divideCeil(uint256 x, uint256 y) private pure returns (uint256) {
        return (x + y - 1) / y;
    }

    function testInitialize() public {
        MangoPublicRegistration newMPR = MangoPublicRegistration(
            address(new TransparentUpgradeableProxy(mangoPublicRegistrationLogic, PROXY_ADMIN, new bytes(0)))
        );

        assertEq(newMPR.owner(), address(0), "BEFORE_OWNER");
        address initializer = address(0x1111);
        vm.prank(initializer);
        newMPR.initialize();
        assertEq(newMPR.owner(), initializer, "AFTER_OWNER");
    }

    function testInitializeTwice() public {
        vm.expectRevert("Initializable: contract is already initialized");
        mangoPublicRegistration.initialize();
    }

    function testMangoSupply() public {
        assertEq(mangoToken.balanceOf(address(mangoPublicRegistration)), INITIAL_MANGO_SUPPLY);
    }

    function testInvalidTimeConstruct() public {
        vm.warp(50);
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_TIME));
        new MangoPublicRegistration(50, address(mangoToken), address(usdcToken));
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_TIME));
        new MangoPublicRegistration(40, address(mangoToken), address(usdcToken));
    }

    function testDepositWhenPaused() public {
        uint256 depositAmount = 100 * (10 ** 6);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);

        mangoPublicRegistration.pause();
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.PAUSED));
        mangoPublicRegistration.deposit(depositAmount);
    }

    function testNormalDeposit() public {
        uint256 depositAmount = 100 * (10 ** 6);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);

        assertEq(usdcToken.balanceOf(address(mangoPublicRegistration)), 0);
        assertEq(mangoPublicRegistration.totalDeposit(), 0);
        assertEq(mangoPublicRegistration.depositAmount(address(this)), 0);

        mangoPublicRegistration.deposit(depositAmount);

        assertEq(usdcToken.balanceOf(address(mangoPublicRegistration)), depositAmount);
        assertEq(mangoPublicRegistration.totalDeposit(), depositAmount);
        assertEq(mangoPublicRegistration.depositAmount(address(this)), depositAmount);
    }

    function testNormalClaim() public {
        uint256 depositAmount = 100 * (10 ** 6);
        uint256 expectedClaimedMangoAmount = (depositAmount * _MANGO_ALLOCATION_AMOUNT) / _USDC_HARDCAP;
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        vm.warp(block.timestamp + 7 days);

        assertEq(mangoToken.balanceOf(address(this)), 0);
        assertEq(mangoPublicRegistration.claimed(address(this)), false);

        mangoPublicRegistration.claim(address(this));

        assertEq(mangoToken.balanceOf(address(this)), expectedClaimedMangoAmount);
        assertEq(mangoPublicRegistration.claimed(address(this)), true);
    }

    function testTransferUsdcToMangoReceiver() public {
        uint256 depositAmount = 100 * (10 ** 6);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        vm.warp(block.timestamp + 7 days);

        assertEq(usdcToken.balanceOf(address(mangoPublicRegistration)), depositAmount);
        assertEq(usdcToken.balanceOf(address(usdcReceiver)), 0);

        mangoPublicRegistration.transferUSDCToReceiver(address(usdcReceiver));

        assertEq(usdcToken.balanceOf(address(mangoPublicRegistration)), 0);
        assertEq(usdcToken.balanceOf(address(usdcReceiver)), depositAmount);
    }

    function testTransferUsdcToMangoReceiverAccess() public {
        uint256 depositAmount = 100 * (10 ** 6);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        vm.warp(block.timestamp + 7 days);

        assertEq(usdcToken.balanceOf(address(mangoPublicRegistration)), depositAmount);
        assertEq(usdcToken.balanceOf(address(usdcReceiver)), 0);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        mangoPublicRegistration.transferUSDCToReceiver(address(usdcReceiver));
    }

    function testDepositMoreThanLimit() public {
        uint256 depositAmount = 2000 * (10 ** 6);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.EXCEEDED_BALANCE));
        mangoPublicRegistration.deposit(depositAmount);
    }

    function testClaimWhenPaused() public {
        uint256 depositAmount = 100 * (10 ** 6);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        mangoPublicRegistration.pause();
        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.PAUSED));
        mangoPublicRegistration.claim(address(this));
    }

    function testClaimBeforeEnd() public {
        uint256 depositAmount = 100 * (10 ** 6);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_TIME));

        mangoPublicRegistration.claim(address(this));
    }

    function testClaimInsufficientBalance() public {
        vm.warp(mangoPublicRegistration.endTime());

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INSUFFICIENT_BALANCE));

        mangoPublicRegistration.claim(address(this));
    }

    function testClaimTwice() public {
        uint256 depositAmount = 100 * (10 ** 6);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        vm.warp(block.timestamp + 7 days);

        mangoPublicRegistration.claim(address(this));

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.ACCESS));

        mangoPublicRegistration.claim(address(this));
    }

    function testTransferUsdcToMangoReceiverBeforeEnd() public {
        uint256 depositAmount = 100 * (10 ** 6);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_TIME));

        mangoPublicRegistration.transferUSDCToReceiver(address(usdcReceiver));
    }

    function testBurnUnsoldMango() public {
        uint256 depositAmount = 80;
        uint256 expectedBurnMangoAmount = _MANGO_ALLOCATION_AMOUNT -
            _divideCeil((depositAmount * _MANGO_ALLOCATION_AMOUNT), _USDC_HARDCAP);
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        vm.warp(block.timestamp + 7 days);

        assertEq(mangoToken.balanceOf(address(mangoPublicRegistration)), INITIAL_MANGO_SUPPLY);

        mangoPublicRegistration.burnUnsoldMango();

        assertEq(mangoToken.balanceOf(address(0xdead)), expectedBurnMangoAmount);
        assertEq(
            mangoToken.balanceOf(address(mangoPublicRegistration)),
            _MANGO_ALLOCATION_AMOUNT - expectedBurnMangoAmount
        );
    }

    function testBurnUnsoldMangoBeforeEnd() public {
        uint256 depositAmount = 80;
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_TIME));

        mangoPublicRegistration.burnUnsoldMango();
    }

    function testBurnUnsoldMangoAccess() public {
        uint256 depositAmount = 80;
        vm.warp(75);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        vm.warp(block.timestamp + 7 days);

        assertEq(mangoToken.balanceOf(address(mangoPublicRegistration)), INITIAL_MANGO_SUPPLY);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        mangoPublicRegistration.burnUnsoldMango();
    }

    function testClaimWhenHardcapExceeded() public {
        uint256 depositAmount = 1000 * (10 ** 6);
        vm.warp(75);

        for (uint16 i = 1; i <= 799; i++) {
            // generate user based on index
            address user = address(bytes20(keccak256(abi.encodePacked(i))));
            usdcToken.transfer(user, depositAmount);
            vm.prank(user);
            usdcToken.approve(address(mangoPublicRegistration), depositAmount);
            vm.prank(user);
            mangoPublicRegistration.deposit(depositAmount);
        }

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);
        mangoPublicRegistration.deposit(depositAmount);

        assertEq(mangoPublicRegistration.totalDeposit(), 800 * depositAmount);

        vm.warp(block.timestamp + 7 days);

        assertEq(mangoToken.balanceOf(address(this)), 0);
        mangoPublicRegistration.claim(address(this));
        assertEq(mangoToken.balanceOf(address(this)), (4_500_000_000 * 10 ** 18) / 800);
    }

    function testDepositBeforeStart() public {
        uint256 depositAmount = 100 * (10 ** 6);
        vm.warp(25);

        usdcToken.approve(address(mangoPublicRegistration), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(Errors.MangoError.selector, Errors.INVALID_TIME));

        mangoPublicRegistration.deposit(depositAmount);
    }
}
