// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "../token/ERC20.sol";
import {Roles} from "../access/Roles.sol";
import {IFlashBorrower, IDepositPayer} from "./IVaultCallbacks.sol";

/// @notice Share vault over USDL. A fifth of the vault's assets stays in the vault as a buffer
/// for redemptions and flash loans; the rest is lent out by the desk, which reports what it is
/// worth. Redemptions are requested, then claimed a day later.
contract LanternVault is ERC20 {
    event Deposit(address indexed account, uint256 assets, uint256 shares);
    event RedeemRequested(address indexed account, uint256 shares, uint256 assets);
    event Claimed(address indexed account, uint256 assets);
    event Rebalanced(uint256 toDesk);
    event Reported(uint256 deployed);
    event Returned(uint256 assets);
    event FlashLoan(address indexed receiver, uint256 amount, uint256 fee);

    uint256 public constant BUFFER_BPS = 2_000;
    uint256 public constant FLASH_FEE_BPS = 9;
    uint256 public constant REDEEM_DELAY = 1 days;
    uint256 internal constant BPS = 10_000;
    /// @dev Counted on both sides of the share price, so that it cannot be moved while the vault
    /// is empty or nearly so.
    uint256 internal constant VIRTUAL = 1e6;

    ERC20 public immutable asset;
    Roles public immutable roles;

    /// @notice USDL held by the vault, amounts awaiting claim included.
    uint256 public idle;
    /// @notice Value of the USDL lent out by the desk, as last reported.
    uint256 public deployed;
    /// @notice USDL owed to redemption requests that have not been claimed yet.
    uint256 public pendingTotal;

    mapping(address => uint256) public pending;
    mapping(address => uint256) public claimableAt;

    modifier onlyOperator() {
        require(msg.sender == roles.operator(), "LanternVault: not operator");
        _;
    }

    constructor(ERC20 asset_, Roles roles_) ERC20("Lantern Vault Share", "lUSDL", 18) {
        asset = asset_;
        roles = roles_;
    }

    /// @notice USDL value backing the outstanding shares.
    function totalAssets() public view returns (uint256) {
        return idle + deployed - pendingTotal;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return (assets * (totalSupply + VIRTUAL)) / (totalAssets() + VIRTUAL);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return (shares * (totalAssets() + VIRTUAL)) / (totalSupply + VIRTUAL);
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        shares = convertToShares(assets);
        require(shares > 0, "LanternVault: zero shares");
        require(asset.transferFrom(msg.sender, address(this), assets), "LanternVault: transfer failed");
        idle += assets;
        _mint(msg.sender, shares);
        emit Deposit(msg.sender, assets, shares);
    }

    /// @notice Deposit paid for from a callback, for routers that source the USDL in the same
    /// transaction. The caller receives the shares, then `onDeposit`, and must have paid by the
    /// time it returns.
    function depositWithCallback(uint256 assets, bytes calldata data) external returns (uint256 shares) {
        shares = convertToShares(assets);
        require(shares > 0, "LanternVault: zero shares");
        idle += assets;
        _mint(msg.sender, shares);
        IDepositPayer(msg.sender).onDeposit(assets, data);
        require(asset.balanceOf(address(this)) >= idle, "LanternVault: deposit not paid");
        emit Deposit(msg.sender, assets, shares);
    }

    /// @notice Burns `shares` and records the USDL they are worth, claimable after the delay.
    function requestRedeem(uint256 shares) external returns (uint256 assets) {
        assets = convertToAssets(shares);
        require(assets > 0, "LanternVault: zero assets");
        _burn(msg.sender, shares);
        pending[msg.sender] += assets;
        pendingTotal += assets;
        claimableAt[msg.sender] = block.timestamp + REDEEM_DELAY;
        emit RedeemRequested(msg.sender, shares, assets);
    }

    function claim() external returns (uint256 assets) {
        require(block.timestamp >= claimableAt[msg.sender], "LanternVault: too early");
        assets = pending[msg.sender];
        require(assets > 0, "LanternVault: nothing to claim");
        pending[msg.sender] = 0;
        pendingTotal -= assets;
        idle -= assets;
        require(asset.transfer(msg.sender, assets), "LanternVault: transfer failed");
        emit Claimed(msg.sender, assets);
    }

    /// @notice Sends what the vault holds beyond the buffer and the pending claims to the desk.
    function rebalance() external returns (uint256 toDesk) {
        uint256 keep = (totalAssets() * BUFFER_BPS) / BPS + pendingTotal;
        require(idle > keep, "LanternVault: nothing to send");
        toDesk = idle - keep;
        idle -= toDesk;
        deployed += toDesk;
        require(asset.transfer(roles.operator(), toDesk), "LanternVault: transfer failed");
        emit Rebalanced(toDesk);
    }

    /// @notice The desk reports what the USDL it holds is worth, gains and losses included.
    function report(uint256 deployed_) external onlyOperator {
        deployed = deployed_;
        emit Reported(deployed_);
    }

    /// @notice The desk returns USDL to the vault.
    function returnFunds(uint256 assets) external onlyOperator {
        deployed -= assets;
        idle += assets;
        require(asset.transferFrom(msg.sender, address(this), assets), "LanternVault: transfer failed");
        emit Returned(assets);
    }

    function flashFee(uint256 amount) public pure returns (uint256) {
        return (amount * FLASH_FEE_BPS) / BPS;
    }

    /// @notice Lends `amount` of the vault's USDL to `receiver` for the length of one call. The
    /// fee goes to the shareholders.
    function flashLoan(IFlashBorrower receiver, uint256 amount, bytes calldata data) external {
        require(amount > 0 && amount <= idle, "LanternVault: bad amount");
        uint256 fee = flashFee(amount);
        require(asset.transfer(address(receiver), amount), "LanternVault: transfer failed");
        receiver.onFlashLoan(msg.sender, amount, fee, data);
        require(asset.balanceOf(address(this)) >= idle + fee, "LanternVault: loan not repaid");
        idle += fee;
        emit FlashLoan(address(receiver), amount, fee);
    }
}
