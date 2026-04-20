// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title ZKBurnVerifier
 * @notice PLONK verifier template for BurnVerifier.circom (N=16).
 *
 * REPLACE with snarkjs output:
 *   snarkjs zkey export solidityverifier circuit_final.zkey contracts/ZKBurnVerifier.sol
 *
 * Public signals: [totalBurned, nullifier[0..15]] — 17 total
 * Proof: uint256[24] (BN254 PLONK encoding)
 */

interface IZKBurnVerifier {
    function verifyProof(
        uint256[24] calldata proof,
        uint256[]   calldata pubSignals
    ) external view returns (bool);
}

/// @dev Stub — replace with snarkjs-generated verifier post-ceremony.
contract ZKBurnVerifier is IZKBurnVerifier {
    function verifyProof(
        uint256[24] calldata,
        uint256[]   calldata
    ) external view override returns (bool) {
        revert("ZKBurnVerifier: stub — run ceremony and replace");
    }
}
