// SPDX-License-Identifier: MIT
pragma solidity 0.8.24; // Pinned: Cancun EVM, EIP-1153 support

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Minimal interface to notify FeeCollector of incoming fees.
interface IFeeCollector {
    function onFeeReceived(uint256 amount) external;
}

/**
 * @title NULLAI
 * @author NULLAI Core Team
 * @notice Deflationary ERC-20 with hard cap, logistic emission, and routed fee collection.
 *
 * Architecture:
 * - HARD_CAP is enforced at mint time; total supply can never exceed 1B.
 * - Every non-exempt transfer routes a configurable fee to FeeCollector.
 * - FeeCollector is notified via `onFeeReceived` so it can update its
 *   EIP-1153 transient accumulator within the same transaction.
 */
contract NULLAI is ERC20, ERC20Burnable, Ownable {

    // ────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────

    uint256 public constant HARD_CAP = 1_000_000_000 * 10 ** 18;

    // Fee cap: owner can set up to 5%, never higher (protects users).
    uint256 public constant MAX_TRANSFER_FEE_BPS = 500;

    // ────────────────────────────────────────────────────────────────────────
    // State
    // ────────────────────────────────────────────────────────────────────────

    /// @notice Logistic emission upper bound (updatable by governance).
    uint256 public emissionL = HARD_CAP;
    /// @notice Logistic decay speed factor in bps.
    uint256 public emissionK = 100;
    /// @notice Emission inflection timestamp (set at deploy).
    uint256 public immutable emissionT0;

    /// @notice Transfer fee in basis points (default 1%).
    uint256 public transferFeeBps = 100;

    /// @notice Address of the FeeCollector contract.
    address public feeCollector;

    /// @notice Accounts exempt from transfer fees (routers, POLManager, etc.)
    mapping(address => bool) public isFeeExempt;

    // ────────────────────────────────────────────────────────────────────────
    // Events
    // ────────────────────────────────────────────────────────────────────────

    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event TransferFeeUpdated(uint256 oldBps, uint256 newBps);
    event FeeExemptUpdated(address indexed account, bool exempt);

    // ────────────────────────────────────────────────────────────────────────
    // Constructor
    // ────────────────────────────────────────────────────────────────────────

    constructor(
        address initialAdmin,
        address _feeCollector,
        uint256 treasuryAllocation
    ) ERC20("NULLAI", "NULLAI") Ownable(initialAdmin) {
        require(_feeCollector != address(0), "NULLAI: zero feeCollector");
        require(treasuryAllocation <= HARD_CAP / 5, "NULLAI: treasury alloc too large");

        feeCollector = _feeCollector;
        emissionT0 = block.timestamp;
        isFeeExempt[_feeCollector] = true;
        _mint(initialAdmin, treasuryAllocation);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Mint (Hard-Cap Enforced)
    // ────────────────────────────────────────────────────────────────────────

    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= HARD_CAP, "NULLAI: hard cap exceeded");
        _mint(to, amount);
    }

    // ────────────────────────────────────────────────────────────────────────
    // Transfer Hook — EIP-1153 Optimized Fee Routing
    // ────────────────────────────────────────────────────────────────────────

    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0) || isFeeExempt[from] || isFeeExempt[to]) {
            super._update(from, to, amount);
            return;
        }

        uint256 fee = (amount * transferFeeBps) / 10_000;

        if (fee == 0) {
            super._update(from, to, amount);
            return;
        }

        uint256 net = amount - fee;
        super._update(from, to, net);
        super._update(from, feeCollector, fee);
        try IFeeCollector(feeCollector).onFeeReceived(fee) {} catch {}
    }

    // ────────────────────────────────────────────────────────────────────────
    // Logistic Emission View
    // ────────────────────────────────────────────────────────────────────────

    function getLogisticSupply(uint256 timestamp) public view returns (uint256) {
        if (timestamp <= emissionT0) return emissionL / 2;
        uint256 elapsed = timestamp - emissionT0;
        uint256 rampDuration = 4 * 365 days;
        if (elapsed >= rampDuration) return emissionL;
        return emissionL / 2 + (elapsed * (emissionL / 2)) / rampDuration;
    }

    // ────────────────────────────────────────────────────────────────────────
    // Admin Setters
    // ────────────────────────────────────────────────────────────────────────

    function setFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "NULLAI: zero address");
        address old = feeCollector;
        isFeeExempt[old] = false;
        feeCollector = newCollector;
        isFeeExempt[newCollector] = true;
        emit FeeCollectorUpdated(old, newCollector);
    }

    function setTransferFee(uint256 bps) external onlyOwner {
        require(bps <= MAX_TRANSFER_FEE_BPS, "NULLAI: fee exceeds 5%");
        emit TransferFeeUpdated(transferFeeBps, bps);
        transferFeeBps = bps;
    }

    function setFeeExempt(address account, bool exempt) external onlyOwner {
        isFeeExempt[account] = exempt;
        emit FeeExemptUpdated(account, exempt);
    }
}
