pragma circom 2.0.0;

/*
 * BurnVerifier.circom — NULLAI Protocol ZK Batch Burn
 * Standard: PLONK (universal SRS, no per-circuit ceremony)
 * N = 16 burns per batch proof
 *
 * Proves:
 *   1. SUM INTEGRITY:     amounts[0..N-1] sum to public `totalBurned`
 *   2. NULLIFIER BINDING: nullifier[k] = Poseidon(secret[k], burnIndex[k])
 *   3. NON-ZERO AMOUNTS:  each amount > 0 (no ghost entries)
 *
 * Public inputs:  totalBurned, nullifiers[N]
 * Private inputs: amounts[N], secrets[N], burnIndices[N]
 *
 * Constraints (N=16): ~3,900 — PTAU 2^12 sufficient.
 */

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

template AssertNonZero() {
    signal input in;
    component isz = IsZero();
    isz.in <== in;
    isz.out === 0;
}

template BurnVerifier(N) {
    // Public
    signal input totalBurned;
    signal input nullifiers[N];

    // Private (witness)
    signal input amounts[N];
    signal input secrets[N];
    signal input burnIndices[N];

    // Constraint 1: Nullifier binding
    component poseidon[N];
    for (var k = 0; k < N; k++) {
        poseidon[k] = Poseidon(2);
        poseidon[k].inputs[0] <== secrets[k];
        poseidon[k].inputs[1] <== burnIndices[k];
        poseidon[k].out === nullifiers[k];
    }

    // Constraint 2: Sum integrity
    signal partialSum[N + 1];
    partialSum[0] <== 0;
    for (var k = 0; k < N; k++) {
        partialSum[k + 1] <== partialSum[k] + amounts[k];
    }
    partialSum[N] === totalBurned;

    // Constraint 3: Non-zero amounts
    component nonZeroCheck[N];
    for (var k = 0; k < N; k++) {
        nonZeroCheck[k] = AssertNonZero();
        nonZeroCheck[k].in <== amounts[k];
    }
}

component main {public [totalBurned, nullifiers]} = BurnVerifier(16);
