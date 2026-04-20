# NULLAI ZK Circuits — Setup

## Prerequisites
```bash
cargo install circom
npm install -g snarkjs
npm install circomlib
```

## 1. Compile
```bash
circom BurnVerifier.circom --r1cs --wasm --sym -l ../node_modules -o build/
```
Expected: ~3,900 constraints (N=16)

## 2. Powers of Tau (universal — no new ceremony needed)
```bash
snarkjs powersoftau download hermez 13 ptau/hermez_final_13.ptau
```

## 3. PLONK Setup
```bash
snarkjs plonk setup build/BurnVerifier.r1cs ptau/hermez_final_13.ptau build/circuit_final.zkey
snarkjs zkey export verificationkey build/circuit_final.zkey build/verification_key.json
```

## 4. Generate Solidity Verifier (REPLACES stub)
```bash
snarkjs zkey export solidityverifier build/circuit_final.zkey ../contracts/ZKBurnVerifier.sol
```

## 5. Operator Bot
```bash
BOT_MASTER_SECRET=0x... RPC_URL=https://... BURN_ENGINE=0x... OPERATOR_PRIVATE_KEY=0x... \
npx ts-node scripts/generateBurnProof.ts
```

## Gas Savings
| Mode | Txs | Gas |
|---|---|---|
| 16 individual burns | 16 | ~1,280,000 |
| 1 ZK batch | 1 | ~430,000 |
| **Saving** | — | **~66%** |
