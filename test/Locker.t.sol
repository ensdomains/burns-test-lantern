// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LanternFixture} from "./utils/LanternFixture.sol";

contract LockerTest is LanternFixture {
    address internal alice = makeAddr("alice");

    function lockAs(address account, uint256 assets) internal {
        fund(account, assets);
        vm.startPrank(account);
        usdl.approve(address(vault), assets);
        vault.approve(address(locker), type(uint256).max);
        locker.lock(vault.deposit(assets));
        vm.stopPrank();
    }

    function addBonus(uint256 amount) internal {
        fund(address(this), amount);
        usdl.approve(address(locker), amount);
        locker.addBonus(amount);
    }

    function test_bonusIsSharedByStake() public {
        lockAs(alice, 300_000e18);
        addBonus(4_000e18);

        vm.prank(alice);
        assertEq(locker.claimBonus(), 3_000e18);
        vm.prank(staker);
        assertEq(locker.claimBonus(), 1_000e18);
    }

    function test_unlockTakesTheCooldown() public {
        vm.startPrank(staker);
        locker.requestUnlock(STAKE);
        vm.expectRevert("LanternLocker: cooling down");
        locker.withdraw();
        vm.warp(block.timestamp + 7 days);
        assertEq(locker.withdraw(), STAKE);
        vm.stopPrank();

        assertEq(vault.balanceOf(staker), STAKE);
        assertEq(locker.totalLocked(), 0);
        assertEq(locker.totalUnlocking(), 0);
    }

    function test_lossIsSettledAgainstEarningStakeFirst() public {
        vm.prank(staker);
        locker.requestUnlock(40_000e18);

        vm.prank(alice);
        vm.expectRevert("LanternLocker: not operator");
        locker.slash(staker, 1e18);

        vm.startPrank(operator);
        locker.slash(staker, 70_000e18);
        assertEq(locker.locked(staker), 0);
        assertEq(locker.unlocking(staker), 30_000e18);
        assertEq(vault.balanceOf(operator), 70_000e18);
        vm.expectRevert("LanternLocker: over the stake");
        locker.slash(staker, 30_000e18 + 1);
        vm.stopPrank();

        assertEq(locker.totalLocked(), 30_000e18);
        assertEq(locker.totalUnlocking(), 30_000e18);
    }
}
