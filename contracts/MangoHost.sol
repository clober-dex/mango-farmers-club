// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./clober/CloberMarketFactory.sol";
import "./interfaces/ICloberMarketHost.sol";
import "./utils/ReentrancyGuard.sol";

contract MangoHost is ICloberMarketHost, Initializable, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    CloberMarketFactory private _marketFactory;
    // token => receiver
    mapping(address => address) public override tokenReceiver;

    function initialize(ITokenReceiver[] calldata receivers_) external initializer {
        _initReentrancyGuard();
        _transferOwnership(msg.sender);
        for (uint256 i = 0; i < receivers_.length; ++i) {
            ITokenReceiver receiver = receivers_[i];
            address token = receiver.receivingToken();
            tokenReceiver[token] = address(receiver);
            setApprovals(token);
        }
    }

    function setApprovals(address token) public {
        address receiver = tokenReceiver[token];
        if (receiver != address(0)) {
            IERC20(token).safeApprove(receiver, 0);
            IERC20(token).safeApprove(receiver, type(uint256).max);
        }
    }

    function distributeTokens(address[] calldata tokenList) external {
        for (uint256 i = 0; i < tokenList.length; ++i) {
            address token = tokenList[i];
            address receiver = tokenReceiver[token];
            if (receiver == address(0)) {
                continue;
            }
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount > 0) {
                ITokenReceiver(receiver).receiveToken(amount);
            }
        }
    }

    function setTokenReceiver(ITokenReceiver receiver) external onlyOwner {
        address token = receiver.receivingToken();
        address oldReceiver = tokenReceiver[token];
        if (oldReceiver != address(0)) {
            IERC20(token).safeApprove(oldReceiver, 0);
        }
        tokenReceiver[token] = address(receiver);
        emit SetTokenReceiver(token, address(receiver));

        setApprovals(token);
    }

    function withdrawLostERC20(address token, address to) external onlyOwner {
        if (tokenReceiver[token] != address(0)) {
            revert Errors.MangoError(Errors.INVALID_ADDRESS);
        }

        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    function receiveHost(address market) external onlyOwner {
        _marketFactory.executeHandOverHost(market);
    }
}
