// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {LanternFixture} from "./utils/LanternFixture.sol";
import {IFlashBorrower, IDepositPayer} from "../src/vault/IVaultCallbacks.sol";
import {LanternVault} from "../src/vault/LanternVault.sol";
import {ERC20} from "../src/token/ERC20.sol";

contract Borrower is IFlashBorrower {
    bool public repay = true;

    function setRepay(bool repay_) external {
        repay = repay_;
    }

    function onFlashLoan(address, uint256 amount, uint256 fee, bytes calldata) external {
        LanternVault vault = LanternVault(msg.sender);
        if (repay) vault.asset().transfer(msg.sender, amount + fee);
    }
}

contract Router is IDepositPayer {
    bool public pay = true;

    function setPay(bool pay_) external {
        pay = pay_;
    }

    function depositFor(LanternVault vault, uint256 assets) external returns (uint256 shares) {
        shares = vault.depositWithCallback(assets, abi.encode(msg.sender));
        vault.transfer(msg.sender, shares);
    }

    function onDeposit(uint256 assets, bytes calldata data) external {
        address from = abi.decode(data, (address));
        if (pay) LanternVault(msg.sender).asset().transferFrom(from, msg.sender, assets);
    }
}

contract VaultTest is LanternFixture {
    address internal alice = makeAddr("alice");

    function test_startingState() public view {
        assertEq(vault.totalSupply(), DEPOSITS);
        assertEq(vault.totalAssets(), DEPOSITS);
        assertEq(vault.idle(), DEPOSITS / 5);
        assertEq(vault.deployed(), (DEPOSITS * 4) / 5);
        assertEq(usdl.balanceOf(address(vault)), vault.idle());
        assertEq(usdl.balanceOf(operator), vault.deployed());
    }

    function test_depositThenRedeemReturnsTheDeposit() public {
        fund(alice, 10_000e18);
        vm.startPrank(alice);
        usdl.approve(address(vault), 10_000e18);
        uint256 shares = vault.deposit(10_000e18);
        assertEq(shares, 10_000e18);

        vault.requestRedeem(shares);
        vm.expectRevert("LanternVault: too early");
        vault.claim();
        vm.warp(block.timestamp + 1 days);
        assertEq(vault.claim(), 10_000e18);
        vm.stopPrank();

        assertEq(usdl.balanceOf(alice), 10_000e18);
        assertEq(vault.pendingTotal(), 0);
        assertEq(usdl.balanceOf(address(vault)), vault.idle());
    }

    function test_rebalanceKeepsTheBufferAndPendingClaims() public {
        vm.expectRevert("LanternVault: nothing to send");
        vault.rebalance();

        fund(alice, 100_000e18);
        vm.startPrank(alice);
        usdl.approve(address(vault), 100_000e18);
        vault.deposit(100_000e18);
        vm.stopPrank();

        assertEq(vault.rebalance(), 80_000e18);
        assertEq(vault.idle(), 220_000e18);
        assertEq(usdl.balanceOf(operator), 880_000e18);
    }

    function test_deskReportsAndReturnsFunds() public {
        vm.expectRevert("LanternVault: not operator");
        vault.report(1);
        vm.expectRevert("LanternVault: not operator");
        vault.returnFunds(1);

        fund(operator, 40_000e18);
        vm.startPrank(operator);
        vault.report(840_000e18);
        assertEq(vault.totalAssets(), 1_040_000e18);
        vault.returnFunds(300_000e18);
        vm.stopPrank();

        assertEq(vault.idle(), 500_000e18);
        assertEq(vault.deployed(), 540_000e18);
        assertEq(usdl.balanceOf(address(vault)), vault.idle());
    }

    function test_flashLoanChargesTheFee() public {
        Borrower borrower = new Borrower();
        uint256 fee = vault.flashFee(100_000e18);
        assertEq(fee, 90e18);
        fund(address(borrower), fee);

        vault.flashLoan(borrower, 100_000e18, "");
        assertEq(vault.idle(), 200_000e18 + fee);
        assertEq(usdl.balanceOf(address(vault)), vault.idle());

        borrower.setRepay(false);
        vm.expectRevert("LanternVault: loan not repaid");
        vault.flashLoan(borrower, 100_000e18, "");

        vm.expectRevert("LanternVault: bad amount");
        vault.flashLoan(borrower, 300_000e18, "");
    }

    function test_depositWithCallbackIsPaidInTheCallback() public {
        Router router = new Router();
        fund(alice, 10_000e18);
        vm.startPrank(alice);
        usdl.approve(address(router), 10_000e18);
        uint256 shares = router.depositFor(vault, 10_000e18);
        vm.stopPrank();

        assertEq(shares, 10_000e18);
        assertEq(vault.balanceOf(alice), 10_000e18);
        assertEq(usdl.balanceOf(address(vault)), vault.idle());

        router.setPay(false);
        vm.prank(alice);
        vm.expectRevert("LanternVault: deposit not paid");
        router.depositFor(vault, 10_000e18);
    }
}
