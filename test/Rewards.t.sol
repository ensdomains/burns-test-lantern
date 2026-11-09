// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LanternFixture} from "./utils/LanternFixture.sol";

contract RewardsTest is LanternFixture {
    address internal alice = makeAddr("alice");

    function test_allocatedRewardIsClaimedOnce() public {
        vm.prank(operator);
        rewards.allocate(alice, 1_000e18);

        vm.startPrank(alice);
        assertEq(rewards.claim(), 1_000e18);
        vm.expectRevert("LanternRewards: nothing allocated");
        rewards.claim();
        vm.stopPrank();
        assertEq(rewards.unclaimed(), 0);
    }

    function test_allocationsStayWithinThePool() public {
        vm.startPrank(operator);
        rewards.allocate(alice, REWARD_POOL);
        vm.expectRevert("LanternRewards: over the pool");
        rewards.allocate(alice, 1);
        vm.stopPrank();
    }

    function test_onlyTheOperatorAllocates() public {
        vm.prank(alice);
        vm.expectRevert("LanternRewards: not operator");
        rewards.allocate(alice, 1e18);
    }
}
