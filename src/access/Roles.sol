// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Who holds which role in Lantern. The owner deploys and wires the contracts. The
/// operator runs the lending desk: it holds the USDL the vault lends out, reports what that is
/// worth, allocates rewards and settles desk losses against lockers.
contract Roles {
    event OperatorSet(address indexed operator);

    address public immutable owner;
    address public operator;

    constructor(address operator_) {
        owner = msg.sender;
        _setOperator(operator_);
    }

    function setOperator(address operator_) external {
        require(msg.sender == owner, "Roles: not owner");
        _setOperator(operator_);
    }

    function _setOperator(address operator_) internal {
        require(operator_ != address(0), "Roles: zero operator");
        operator = operator_;
        emit OperatorSet(operator_);
    }
}
