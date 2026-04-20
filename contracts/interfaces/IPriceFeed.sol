// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IPriceFeed
 * @author NULLAI Core Team
 * @notice Dual-oracle interface (Chainlink external + Uniswap V4 TWAP internal).
 *
 * Security: checkSanity does NOT accept a caller-supplied TWAP;
 * implementors must derive it trustlessly from the pool's observation array.
 */
interface IPriceFeed {

    struct PriceReport {
        uint256 externalPrice;    // Chainlink/Pyth price, 18-decimal
        uint256 internalTwap;     // Uniswap V4 TWAP, 18-decimal
        uint256 deviationBps;     // |external - twap| * 10_000 / twap
        uint256 externalUpdatedAt;
        bool    isConsistent;
        bool    inSafeMode;
    }

    function getLatestPrice() external view returns (uint256 price);
    function getTWAP() external view returns (uint256 twap);

    /**
     * @param thresholdBps Max allowed deviation (e.g. 1000 = 10%).
     * @return consistent  True if both oracles agree within threshold.
     * @return deviationBps Actual measured deviation.
     */
    function checkSanity(uint256 thresholdBps)
        external view returns (bool consistent, uint256 deviationBps);

    function getFullReport() external view returns (PriceReport memory);
}
