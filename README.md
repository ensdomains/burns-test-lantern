# Lantern

> [!WARNING]
> **This is test material for an automated code audit tool, not a real protocol.** It has never
> been reviewed or deployed, and it is not maintained. Do not deploy it, copy it into other
> projects, or send it real funds.

Lantern is a small savings protocol. Depositors put USDL into a share vault. A fifth of the
vault's assets stays in the vault to serve redemptions and flash loans, and the rest is lent out
by Lantern's lending desk, which reports what it is worth. Lockers stake vault shares as
first-loss cover for the desk and earn bonuses for it, and a points programme pays USDL rewards.

## Contracts

| Contract                     | What it does                                                                    |
| ---------------------------- | ------------------------------------------------------------------------------- |
| `token/ERC20.sol`            | Minimal ERC-20 base                                                             |
| `token/LanternDollar.sol`    | USDL, minted by the owner against off-chain reserves                            |
| `access/Roles.sol`           | The owner and the desk operator                                                 |
| `vault/LanternVault.sol`     | Share vault over USDL: deposits, delayed redemptions, the desk, flash loans     |
| `vault/IVaultCallbacks.sol`  | Callbacks for flash loans and for deposits paid from a callback                 |
| `rewards/LanternRewards.sol` | Rewards the desk allocates and accounts claim                                   |
| `locker/LanternLocker.sol`   | Locked vault shares: bonuses, a cooldown to leave, losses settled against stake |

## Roles

- **Owner**: deploys and wires the contracts, appoints the operator and mints USDL.
- **Operator**: runs the lending desk. It receives the USDL the vault sends out, returns it,
  reports its value, allocates rewards and settles desk losses against lockers.

## Build and test

```sh
git clone --depth 1 --branch v1.9.7 https://github.com/foundry-rs/forge-std lib/forge-std
forge test
```

Solidity 0.8.28. `test/utils/LanternFixture.sol` deploys and wires the system.
