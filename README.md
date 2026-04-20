# NULLAI Protocol — Core V4 Pro

> Deflationary ERC-20 with Dynamic Volatility Burn, Uniswap V4 POL Management, and EIP-1153 Optimized Fee Collection.

---

## Architecture Overview

```
User Transfer
    │
    ▼
NULLAI._update()
    │  1% fee → FeeCollector
    │  onFeeReceived() callback (TSTORE accumulate)
    │
    ▼
FeeCollector.flush()  [triggered at 10k NULLAI threshold]
    ├── 50% → BurnEngine.scheduleBurn()
    ├──  5% → POLManager.seedPOL()
    ├── 30% → ISB Reserve (held)
    └── 15% → Anti-MEV Reserve (held)

Uniswap V4 Pool
    │
    ▼
NULLAIHooks.beforeSwap()  [TSTORE price snapshot]
    │
    ▼
NULLAIHooks.afterSwap()   [compute volatility bps]
    │  → BurnEngine.recordVolatility()
    │  → TSTORE volatility for LP guard
    ▼
NULLAIHooks.beforeAddLiquidity()  [block if volatility > 5%]
```

---

## Core Technical Features

### EIP-1153: Transient Storage Optimization

All intra-transaction state uses `TSTORE`/`TLOAD` (Ethereum Cancun, Solidity 0.8.24):
- **FeeCollector**: accumulates fees within a tx without SSTORE — gas saved per transfer.
- **NULLAIHooks**: passes price snapshots and volatility between hook calls with zero permanent storage cost.

### Dual-Oracle Sanity Check

`IPriceFeed.checkSanity(thresholdBps)` compares:
- **Source A**: Chainlink / Pyth external price feed.
- **Source B**: Uniswap V4 15-min TWAP (derived trustlessly from pool observations).

If deviation exceeds 10% (1000 bps) → **Safe Mode** activates: burn rate resets to minimum, POL seeding halts.

### Uniswap V4 Hook (NULLAIHooks)

| Hook | Action |
|---|---|
| `beforeSwap` | TSTORE pre-swap `sqrtPriceX96` + set reentrancy guard |
| `afterSwap` | Compute `volatilityBps = delta * 10000 / sqrtPriceBefore`, dispatch to BurnEngine, **always** clear guard |
| `beforeAddLiquidity` | Revert if `volatilityBps > maxLPVolatilityBps` (default 5%) |

---

## Audit & Fixes Log

> Conducted on 2026-04-20. 13 issues resolved across 6 files.

### Critical Bugs Fixed 🔴

| Bug | File | Impact |
|---|---|---|
| EIP-1153 lock set in `beforeSwap`, never cleared | `NULLAIHooks.sol` | Pool permanently bricked after first swap |
| `onFeeReceived()` never called from `_update` | `NULLAI.sol` | Entire fee accumulation system was a no-op |
| Hard cap never enforced on `mint` | `NULLAI.sol` | Supply expandable beyond 1B tokens |
| `forceSync()` corrupted accounting without token backing | `FeeCollector.sol` | Fee ledger manipulable by owner |

### Security Issues Fixed 🟠

| Issue | Fix |
|---|---|
| Only 2 of 4 allocation buckets defined | Added `isbRatio` + `antiMevRatio`; enforced `sum == 10_000` |
| `ADMIN_ROLE = 0` collides with OZ `PUBLIC_ROLE` | Renumbered to `10 / 20 / 30` |
| `checkSanity` accepted caller-supplied TWAP | Removed the parameter; implementors fetch TWAP trustlessly |
| Volatility measured as raw absolute delta | Normalized to `bps = delta * 10_000 / sqrtPriceBefore` |
| `afterSwap` never dispatched to `burnEngine` | Calls `recordVolatility()` wrapped in `try/catch` |

### Improvements 🟡

- Unified `pragma` to `0.8.24` (Cancun) across all contracts.
- `isFeeExempt` whitelist with auto-exempt on `setFeeCollector`.
- Full event coverage (`TransferFeeUpdated`, `FeeExemptUpdated`, `FeeFlushed`, `Allocated`).
- `ReentrancyGuard` on `FeeCollector.flush()`, `withdrawISB()`, `distributeAntiMEV()`.
- `pendingBalance()` view correctly excludes locked reserves.
- `hardhat.config.ts` + `tsconfig.json` for Cancun EVM build.

---

## Project Structure

```
/contracts
  NULLAI.sol              # ERC-20 token (hard cap, logistic emission, fee routing)
  FeeCollector.sol        # Fee hub (EIP-1153, 4-bucket allocation)
  AccessControl.sol       # Role hierarchy (Admin/Guardian/Operator)
  /hooks
    NULLAIHooks.sol       # Uniswap V4 hook (volatility burn, LP guard)
  /interfaces
    IPriceFeed.sol        # Dual-oracle interface
/test                     # Hardhat test suite (TBD)
/circuits                 # ZK-SNARK circuits for batch burn verification (TBD)
hardhat.config.ts
tsconfig.json
```

---

## Setup

```bash
npm install
npx hardhat compile
npx hardhat test
```

---

## Deployment Order

1. Deploy `NULLAIAccessControl(dao, guardian, bot)`
2. Deploy `FeeCollector(dao)`
3. Deploy `NULLAI(dao, feeCollector, treasuryAmount)`
4. Deploy `BurnEngine` + `POLManager`
5. Call `FeeCollector.setNullai(nullai)` + `setEngines(burnEngine, polManager)`
6. Deploy `NULLAIHooks(poolManager, burnEngine)`

---

## License

MIT
