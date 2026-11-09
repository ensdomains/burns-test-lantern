// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "../token/ERC20.sol";
import {Roles} from "../access/Roles.sol";

/// @notice Lockers stake vault shares as first-loss cover for the desk and earn USDL bonuses for
/// it. Leaving takes a seven-day cooldown, during which the stake earns nothing and can still be
/// called on. When the desk realises a loss, it is settled against lockers' stakes.
contract LanternLocker {
    event Locked(address indexed account, uint256 amount);
    event UnlockRequested(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event BonusAdded(uint256 amount);
    event BonusClaimed(address indexed account, uint256 amount);
    event Slashed(address indexed account, uint256 amount);

    uint256 public constant COOLDOWN = 7 days;
    uint256 internal constant ONE = 1e18;

    ERC20 public immutable shares;
    ERC20 public immutable bonusToken;
    Roles public immutable roles;

    /// @notice Every share held for lockers.
    uint256 public totalLocked;
    /// @notice The part of `totalLocked` that is in cooldown.
    uint256 public totalUnlocking;
    /// @notice Bonus paid so far per earning share, scaled by 1e18.
    uint256 public bonusPerShare;

    mapping(address => uint256) public locked;
    mapping(address => uint256) public unlocking;
    mapping(address => uint256) public unlockAt;
    mapping(address => uint256) public bonusOwed;
    mapping(address => uint256) internal bonusPaidPerShare;

    constructor(ERC20 shares_, ERC20 bonusToken_, Roles roles_) {
        shares = shares_;
        bonusToken = bonusToken_;
        roles = roles_;
    }

    function lock(uint256 amount) external {
        require(amount > 0, "LanternLocker: zero amount");
        _settle(msg.sender);
        require(shares.transferFrom(msg.sender, address(this), amount), "LanternLocker: transfer failed");
        locked[msg.sender] += amount;
        totalLocked += amount;
        emit Locked(msg.sender, amount);
    }

    /// @notice Starts the cooldown for `amount` of the caller's stake.
    function requestUnlock(uint256 amount) external {
        require(amount > 0, "LanternLocker: zero amount");
        _settle(msg.sender);
        locked[msg.sender] -= amount;
        unlocking[msg.sender] += amount;
        totalUnlocking += amount;
        unlockAt[msg.sender] = block.timestamp + COOLDOWN;
        emit UnlockRequested(msg.sender, amount);
    }

    function withdraw() external returns (uint256 amount) {
        require(block.timestamp >= unlockAt[msg.sender], "LanternLocker: cooling down");
        amount = unlocking[msg.sender];
        require(amount > 0, "LanternLocker: nothing to withdraw");
        unlocking[msg.sender] = 0;
        totalUnlocking -= amount;
        totalLocked -= amount;
        require(shares.transfer(msg.sender, amount), "LanternLocker: transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Shares `amount` of USDL among the lockers whose stake is earning.
    function addBonus(uint256 amount) external {
        uint256 earning = _earning();
        require(earning > 0, "LanternLocker: nobody to pay");
        require(bonusToken.transferFrom(msg.sender, address(this), amount), "LanternLocker: transfer failed");
        bonusPerShare += (amount * ONE) / earning;
        emit BonusAdded(amount);
    }

    function claimBonus() external returns (uint256 amount) {
        _settle(msg.sender);
        amount = bonusOwed[msg.sender];
        require(amount > 0, "LanternLocker: no bonus");
        bonusOwed[msg.sender] = 0;
        require(bonusToken.transfer(msg.sender, amount), "LanternLocker: transfer failed");
        emit BonusClaimed(msg.sender, amount);
    }

    /// @notice Settles a desk loss against `account`'s stake: earning stake first, then stake in
    /// cooldown. The shares go to the desk.
    function slash(address account, uint256 amount) external {
        require(msg.sender == roles.operator(), "LanternLocker: not operator");
        _settle(account);
        uint256 fromLocked = amount < locked[account] ? amount : locked[account];
        uint256 fromUnlocking = amount - fromLocked;
        require(fromUnlocking <= unlocking[account], "LanternLocker: over the stake");
        locked[account] -= fromLocked;
        unlocking[account] -= fromUnlocking;
        totalUnlocking -= fromUnlocking;
        totalLocked -= amount;
        require(shares.transfer(msg.sender, amount), "LanternLocker: transfer failed");
        emit Slashed(account, amount);
    }

    function _earning() internal view returns (uint256) {
        return totalLocked - totalUnlocking;
    }

    function _settle(address account) internal {
        uint256 perShare = bonusPerShare;
        bonusOwed[account] += (locked[account] * (perShare - bonusPaidPerShare[account])) / ONE;
        bonusPaidPerShare[account] = perShare;
    }
}
