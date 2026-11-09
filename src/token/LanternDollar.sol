// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "./ERC20.sol";

/// @notice USDL, the dollar token Lantern takes in deposit. The owner mints it against reserves
/// held off-chain.
contract LanternDollar is ERC20 {
    address public immutable owner;

    constructor() ERC20("Lantern Dollar", "USDL", 18) {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "LanternDollar: not owner");
        _mint(to, amount);
    }
}
