// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IBurnEngine {
    function scheduleBurn(uint256 amount) external;
}

interface IPOLManager {
    function seedPOL(uint256 amount) external;
}

/**
 * @title FeeCollector
 * @author NULLAI Core Team
 * @notice Central hub: receives transfer fees, accumulates via EIP-1153 TSTORE,
 *         dispatches to 4 allocation buckets when flush threshold is crossed.
 *
 * Buckets (default): 50% Burn | 5% POL | 30% ISB | 15% Anti-MEV
 */
contract FeeCollector is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 private constant TX_FEE_SLOT = keccak256("nullai.fee_collector.tx_fees");

    IERC20 public nullai;
    IBurnEngine public burnEngine;
    IPOLManager public polManager;

    uint256 public burnRatio    = 5_000;
    uint256 public polRatio     =   500;
    uint256 public isbRatio     = 3_000;
    uint256 public antiMevRatio = 1_500;

    uint256 public totalFeesCollected;
    uint256 public flushThreshold = 10_000 * 10 ** 18;
    uint256 public isbReserve;
    uint256 public antiMevReserve;

    event FeeReceived(address indexed from, uint256 amount);
    event FeeFlushed(uint256 totalFlushed, uint256 timestamp);
    event Allocated(uint256 burnAmount, uint256 polAmount, uint256 isbAmount, uint256 antiMevAmount);
    event RatiosUpdated(uint256 burn, uint256 pol, uint256 isb, uint256 antiMev);
    event FlushThresholdUpdated(uint256 newThreshold);
    event NullaiSet(address indexed nullai);
    event EnginesSet(address indexed burnEngine, address indexed polManager);

    constructor(address initialAdmin) Ownable(initialAdmin) {}

    function setNullai(address _nullai) external onlyOwner {
        require(_nullai != address(0), "FeeCollector: zero address");
        nullai = IERC20(_nullai);
        emit NullaiSet(_nullai);
    }

    function setEngines(address _burnEngine, address _polManager) external onlyOwner {
        require(_burnEngine != address(0) && _polManager != address(0), "FeeCollector: zero address");
        burnEngine = IBurnEngine(_burnEngine);
        polManager = IPOLManager(_polManager);
        emit EnginesSet(_burnEngine, _polManager);
    }

    function onFeeReceived(uint256 amount) external {
        require(msg.sender == address(nullai), "FeeCollector: caller not NULLAI");
        require(amount > 0, "FeeCollector: zero fee");

        uint256 txTotal;
        assembly {
            txTotal := tload(TX_FEE_SLOT)
            txTotal := add(txTotal, amount)
            tstore(TX_FEE_SLOT, txTotal)
        }

        emit FeeReceived(msg.sender, amount);

        uint256 balance = nullai.balanceOf(address(this)) - isbReserve - antiMevReserve;
        if (balance >= flushThreshold) {
            _flush(balance);
        }
    }

    function flush() external nonReentrant {
        uint256 balance = nullai.balanceOf(address(this)) - isbReserve - antiMevReserve;
        require(balance > 0, "FeeCollector: nothing to flush");
        _flush(balance);
    }

    function _flush(uint256 amount) internal {
        totalFeesCollected += amount;

        uint256 burnAmount    = (amount * burnRatio)    / 10_000;
        uint256 polAmount     = (amount * polRatio)     / 10_000;
        uint256 isbAmount     = (amount * isbRatio)     / 10_000;
        uint256 antiMevAmount = amount - burnAmount - polAmount - isbAmount;

        isbReserve     += isbAmount;
        antiMevReserve += antiMevAmount;

        if (burnAmount > 0 && address(burnEngine) != address(0)) {
            nullai.safeTransfer(address(burnEngine), burnAmount);
            burnEngine.scheduleBurn(burnAmount);
        }

        if (polAmount > 0 && address(polManager) != address(0)) {
            nullai.safeTransfer(address(polManager), polAmount);
            polManager.seedPOL(polAmount);
        }

        assembly { tstore(TX_FEE_SLOT, 0) }

        emit FeeFlushed(amount, block.timestamp);
        emit Allocated(burnAmount, polAmount, isbAmount, antiMevAmount);
    }

    function withdrawISB(address to, uint256 amount) external onlyOwner nonReentrant {
        require(amount <= isbReserve, "FeeCollector: exceeds ISB reserve");
        isbReserve -= amount;
        nullai.safeTransfer(to, amount);
    }

    function distributeAntiMEV(address to, uint256 amount) external onlyOwner nonReentrant {
        require(amount <= antiMevReserve, "FeeCollector: exceeds AntiMEV reserve");
        antiMevReserve -= amount;
        nullai.safeTransfer(to, amount);
    }

    function setRatios(uint256 _burnRatio, uint256 _polRatio, uint256 _isbRatio, uint256 _antiMevRatio) external onlyOwner {
        require(_burnRatio + _polRatio + _isbRatio + _antiMevRatio == 10_000, "FeeCollector: ratios must sum to 10000");
        burnRatio = _burnRatio; polRatio = _polRatio; isbRatio = _isbRatio; antiMevRatio = _antiMevRatio;
        emit RatiosUpdated(_burnRatio, _polRatio, _isbRatio, _antiMevRatio);
    }

    function setFlushThreshold(uint256 threshold) external onlyOwner {
        require(threshold > 0, "FeeCollector: zero threshold");
        flushThreshold = threshold;
        emit FlushThresholdUpdated(threshold);
    }

    function pendingBalance() external view returns (uint256) {
        uint256 total = nullai.balanceOf(address(this));
        uint256 locked = isbReserve + antiMevReserve;
        return total > locked ? total - locked : 0;
    }
}
