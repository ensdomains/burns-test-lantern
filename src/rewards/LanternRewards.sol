// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "../token/ERC20.sol";
import {Roles} from "../access/Roles.sol";

/// @notice USDL rewards for Lantern's users. The points programme runs off-chain; the desk
/// allocates each account's reward here and the account claims it.
contract LanternRewards {
    event Allocated(address indexed account, uint256 amount);
    event Claimed(address indexed account, uint256 amount);

    ERC20 public immutable token;
    Roles public immutable roles;

    /// @notice Allocated and not yet claimed.
    uint256 public unclaimed;
    mapping(address => uint256) public allocated;

    constructor(ERC20 token_, Roles roles_) {
        token = token_;
        roles = roles_;
    }

    function allocate(address account, uint256 amount) external {
        require(msg.sender == roles.operator(), "LanternRewards: not operator");
        require(unclaimed + amount <= token.balanceOf(address(this)), "LanternRewards: over the pool");
        allocated[account] += amount;
        unclaimed += amount;
        emit Allocated(account, amount);
    }

    function claim() external returns (uint256 amount) {
        amount = allocated[msg.sender];
        require(amount > 0, "LanternRewards: nothing allocated");
        allocated[msg.sender] = 0;
        unclaimed -= amount;
        require(token.transfer(msg.sender, amount), "LanternRewards: transfer failed");
        emit Claimed(msg.sender, amount);
    }
}
