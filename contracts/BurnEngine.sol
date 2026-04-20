// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20Burnable} from "./interfaces/IERC20Burnable.sol";
import {IZKBurnVerifier} from "./ZKBurnVerifier.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BurnEngine
 * @author NULLAI Core Team
 * @notice Dynamic deflationary burn engine.
 *
 * Burn rate = clamp(BASE + ewaVolatilityBps * multiplier, BASE, MAX)
 * ZK proof required to execute batch burns — prevents unchecked supply reduction.
 * Nullifier registry prevents replay attacks.
 */
contract BurnEngine is Ownable, ReentrancyGuard {

    uint256 private constant BATCH_SIZE      = 16;
    uint256 private constant PUB_SIGNALS_LEN = BATCH_SIZE + 1; // totalBurned + 16 nullifiers

    uint256 public constant BASE_BURN_RATE = 100;   // 1%
    uint256 public constant MAX_BURN_RATE  = 5_000; // 50%
    uint256 public constant EWA_ALPHA      = 10;

    uint256 public volatilityMultiplier = 15;
    uint256 public ewaVolatilityBps;

    IERC20Burnable  public nullai;
    IZKBurnVerifier public verifier;

    uint256 public pendingBurnAmount;
    uint256 public totalBurned;
    uint256 public burnNonce;

    mapping(bytes32 => bool) public usedNullifiers;

    address public operator;
    address public hooksContract;

    event BurnScheduled(uint256 amount, uint256 newPending, uint256 burnNonce);
    event BatchBurnExecuted(uint256 totalBurned, uint256 batchSize, uint256 burnRate);
    event VolatilityUpdated(uint256 instantBps, uint256 newEwaBps);
    event OperatorUpdated(address indexed newOperator);
    event HooksUpdated(address indexed newHooks);
    event VerifierUpdated(address indexed newVerifier);

    constructor(
        address initialAdmin,
        address _nullai,
        address _verifier,
        address _operator,
        address _hooks
    ) Ownable(initialAdmin) {
        require(_nullai   != address(0), "BurnEngine: zero nullai");
        require(_verifier != address(0), "BurnEngine: zero verifier");
        require(_operator != address(0), "BurnEngine: zero operator");
        require(_hooks    != address(0), "BurnEngine: zero hooks");
        nullai        = IERC20Burnable(_nullai);
        verifier      = IZKBurnVerifier(_verifier);
        operator      = _operator;
        hooksContract = _hooks;
    }

    // Called by NULLAIHooks.afterSwap
    function recordVolatility(uint256 instantBps) external {
        require(msg.sender == hooksContract, "BurnEngine: caller not hooks");
        ewaVolatilityBps = (ewaVolatilityBps * (EWA_ALPHA - 1) + instantBps) / EWA_ALPHA;
        emit VolatilityUpdated(instantBps, ewaVolatilityBps);
    }

    // Called by FeeCollector._flush
    function scheduleBurn(uint256 amount) external {
        require(amount > 0, "BurnEngine: zero amount");
        pendingBurnAmount += amount;
        burnNonce += 1;
        emit BurnScheduled(amount, pendingBurnAmount, burnNonce);
    }

    // Called by OPERATOR bot with ZK proof
    function executeBatchBurn(
        uint256[24] calldata proof,
        uint256[]   calldata pubSignals
    ) external nonReentrant {
        require(msg.sender == operator, "BurnEngine: caller not operator");
        require(pubSignals.length == PUB_SIGNALS_LEN, "BurnEngine: wrong pubSignals length");
        require(verifier.verifyProof(proof, pubSignals), "BurnEngine: invalid ZK proof");

        uint256 provedTotal = pubSignals[0];
        require(provedTotal > 0,                 "BurnEngine: zero burn total");
        require(provedTotal <= pendingBurnAmount, "BurnEngine: total exceeds pending");

        uint256 burnRate     = effectiveBurnRate();
        uint256 effectiveBurn = (provedTotal * burnRate) / 10_000;

        for (uint256 i = 1; i <= BATCH_SIZE; i++) {
            bytes32 nullifier = bytes32(pubSignals[i]);
            require(!usedNullifiers[nullifier], "BurnEngine: nullifier replayed");
            usedNullifiers[nullifier] = true;
        }

        pendingBurnAmount -= provedTotal;
        totalBurned       += effectiveBurn;

        uint256 surplus = provedTotal - effectiveBurn;
        if (surplus > 0) pendingBurnAmount += surplus;

        nullai.burn(effectiveBurn);
        emit BatchBurnExecuted(effectiveBurn, BATCH_SIZE, burnRate);
    }

    function effectiveBurnRate() public view returns (uint256) {
        uint256 rate = BASE_BURN_RATE + ewaVolatilityBps * volatilityMultiplier;
        return rate > MAX_BURN_RATE ? MAX_BURN_RATE : rate;
    }

    function setOperator(address newOp) external onlyOwner {
        require(newOp != address(0), "BurnEngine: zero address");
        operator = newOp; emit OperatorUpdated(newOp);
    }
    function setHooks(address newHooks) external onlyOwner {
        require(newHooks != address(0), "BurnEngine: zero address");
        hooksContract = newHooks; emit HooksUpdated(newHooks);
    }
    function setVerifier(address newVerifier) external onlyOwner {
        require(newVerifier != address(0), "BurnEngine: zero address");
        verifier = IZKBurnVerifier(newVerifier); emit VerifierUpdated(newVerifier);
    }
    function setVolatilityMultiplier(uint256 m) external onlyOwner {
        require(m <= 50, "BurnEngine: too large"); volatilityMultiplier = m;
    }
}
