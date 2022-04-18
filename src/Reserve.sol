// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.7;

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

interface IReserve {
    function withdraw(
        IERC20 token,
        address to,
        uint256 amt
    ) external;

    function deposit(
        IERC20 token,
        address from,
        uint256 amt
    ) external;
}

interface IReservePlugin {
    function afterDeposition(IERC20 token, uint256 amt) external;

    function beforeWithdrawal(IERC20 token, uint256 amt) external;
}

contract Reserve is IReserve, Ownable {
    IReservePlugin public constant NO_PLUGIN = IReservePlugin(address(0));

    mapping(address => bool) public isUser;
    mapping(IERC20 => uint256) public deposited;
    mapping(IERC20 => IReservePlugin) public plugins;

    event PluginSet(
        address owner,
        IERC20 indexed token,
        IReservePlugin indexed oldPlugin,
        IReservePlugin indexed newPlugin
    );
    event Withdrawn(address user, IERC20 indexed token, address indexed to, uint256 amt);
    event Deposited(address user, IERC20 indexed token, address indexed from, uint256 amt);
    event ForceWithdrawn(
        address owner,
        IERC20 indexed token,
        IReservePlugin indexed plugin,
        address indexed to,
        uint256 amt
    );
    event UserAdded(address owner, address indexed user);
    event UserRemoved(address owner, address indexed user);

    constructor(address owner) {
        transferOwnership(owner);
    }

    modifier onlyUser() {
        require(isUser[msg.sender], "Reserve: caller is not the user");
        _;
    }

    function setPlugin(IERC20 token, IReservePlugin newPlugin) public onlyOwner {
        IReservePlugin oldPlugin = plugins[token];
        plugins[token] = newPlugin;
        uint256 amt = deposited[token];
        _beforeWithdrawal(token, oldPlugin, amt);
        _transfer(token, _pluginAddr(oldPlugin), _pluginAddr(newPlugin), amt);
        _afterDeposition(token, newPlugin, amt);
        emit PluginSet(msg.sender, token, oldPlugin, newPlugin);
    }

    function deposit(
        IERC20 token,
        address from,
        uint256 amt
    ) public override onlyUser {
        deposited[token] += amt;
        IReservePlugin plugin = plugins[token];
        _transfer(token, from, _pluginAddr(plugin), amt);
        _afterDeposition(token, plugin, amt);
        emit Deposited(msg.sender, token, from, amt);
    }

    function withdraw(
        IERC20 token,
        address to,
        uint256 amt
    ) public override onlyUser {
        uint256 balance = deposited[token];
        require(balance >= amt, "Reserve: withdrawal over balance");
        deposited[token] = balance - amt;
        IReservePlugin plugin = plugins[token];
        _beforeWithdrawal(token, plugin, amt);
        _transfer(token, _pluginAddr(plugin), to, amt);
        emit Withdrawn(msg.sender, token, to, amt);
    }

    function forceWithdraw(
        IERC20 token,
        IReservePlugin plugin,
        address to,
        uint256 amt
    ) public onlyOwner {
        _beforeWithdrawal(token, plugin, amt);
        _transfer(token, _pluginAddr(plugin), to, amt);
        emit ForceWithdrawn(msg.sender, token, plugin, to, amt);
    }

    function setDeposited(IERC20 token, uint256 amt) public onlyOwner {
        deposited[token] = amt;
    }

    function addUser(address user) public onlyOwner {
        isUser[user] = true;
        emit UserAdded(msg.sender, user);
    }

    function removeUser(address user) public onlyOwner {
        isUser[user] = false;
        emit UserRemoved(msg.sender, user);
    }

    function _afterDeposition(
        IERC20 token,
        IReservePlugin plugin,
        uint256 amt
    ) internal {
        if (plugin != NO_PLUGIN) plugin.afterDeposition(token, amt);
    }

    function _beforeWithdrawal(
        IERC20 token,
        IReservePlugin plugin,
        uint256 amt
    ) internal {
        if (plugin != NO_PLUGIN) plugin.beforeWithdrawal(token, amt);
    }

    function _pluginAddr(IReservePlugin plugin) internal view returns (address) {
        return plugin == NO_PLUGIN ? address(this) : address(plugin);
    }

    function _transfer(
        IERC20 token,
        address from,
        address to,
        uint256 amt
    ) internal {
        bool success;
        if (from == address(this)) {
            success = token.transfer(to, amt);
        } else {
            success = token.transferFrom(from, to, amt);
        }
        require(success, "Reserve: transfer failed");
    }
}
