// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Implemented by a contract that borrows from the vault within one transaction.
interface IFlashBorrower {
    /// @dev Called after `amount` has been sent. `amount + fee` must be back in the vault when
    /// this returns.
    function onFlashLoan(address initiator, uint256 amount, uint256 fee, bytes calldata data) external;
}

/// @notice Implemented by a contract that pays for a deposit from inside a callback.
interface IDepositPayer {
    /// @dev Called after the shares have been issued. `assets` must have been sent to the vault
    /// when this returns.
    function onDeposit(uint256 assets, bytes calldata data) external;
}
