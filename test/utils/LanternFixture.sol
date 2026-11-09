// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "../../src/token/ERC20.sol";
import {LanternDollar} from "../../src/token/LanternDollar.sol";
import {Roles} from "../../src/access/Roles.sol";
import {LanternVault} from "../../src/vault/LanternVault.sol";
import {LanternRewards} from "../../src/rewards/LanternRewards.sol";
import {LanternLocker} from "../../src/locker/LanternLocker.sol";

/// @notice Deploys and wires Lantern as it runs on mainnet: a million USDL deposited, four fifths
/// of it out at the desk, a staker's shares locked and the reward pool funded. The test contract
/// is the deployer and owner.
abstract contract LanternFixture is Test {
    uint256 internal constant DEPOSITS = 1_000_000e18;
    uint256 internal constant STAKE = 100_000e18;
    uint256 internal constant REWARD_POOL = 50_000e18;

    LanternDollar internal usdl;
    Roles internal roles;
    LanternVault internal vault;
    LanternRewards internal rewards;
    LanternLocker internal locker;

    address internal operator = makeAddr("operator");
    address internal depositor = makeAddr("depositor");
    address internal staker = makeAddr("staker");

    function setUp() public virtual {
        usdl = new LanternDollar();
        roles = new Roles(operator);
        vault = new LanternVault(usdl, roles);
        rewards = new LanternRewards(usdl, roles);
        locker = new LanternLocker(vault, usdl, roles);

        usdl.mint(depositor, DEPOSITS - STAKE);
        vm.startPrank(depositor);
        usdl.approve(address(vault), type(uint256).max);
        vault.deposit(DEPOSITS - STAKE);
        vm.stopPrank();

        usdl.mint(staker, STAKE);
        vm.startPrank(staker);
        usdl.approve(address(vault), type(uint256).max);
        vault.approve(address(locker), type(uint256).max);
        locker.lock(vault.deposit(STAKE));
        vm.stopPrank();

        // The desk takes what is beyond the buffer, and can return it.
        vault.rebalance();
        vm.prank(operator);
        usdl.approve(address(vault), type(uint256).max);

        usdl.mint(address(rewards), REWARD_POOL);
    }

    /// @dev Gives `to` USDL, minted by the owner (this contract).
    function fund(address to, uint256 amount) internal {
        usdl.mint(to, amount);
    }
}
