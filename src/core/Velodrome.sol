// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "../IERC20.sol";
import {UnsafeMath} from "../utils/UnsafeMath.sol";
import {SafeTransferLib} from "../vendor/SafeTransferLib.sol";
import {TooMuchSlippage} from "./SettlerErrors.sol";

interface IVelodromePair {
    function metadata()
        external
        view
        returns (
            uint256 basis0,
            uint256 basis1,
            uint256 reserve0,
            uint256 reserve1,
            bool stable,
            IERC20 token0,
            IERC20 token1
        );
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

abstract contract Velodrome {
    using UnsafeMath for uint256;
    using SafeTransferLib for IERC20;

    uint256 private constant _BASIS = 1 ether;

    function _k(uint256 x, uint256 y) private pure returns (uint256) {
        unchecked {
            return (x * y / _BASIS) * (x * x / _BASIS + y * y / _BASIS) / _BASIS; // x3y+y3x
        }
    }

    function _f(uint256 x0, uint256 y) private pure returns (uint256) {
        unchecked {
            return y * y / _BASIS * y / _BASIS * x0 / _BASIS + x0 * x0 / _BASIS * x0 / _BASIS * y / _BASIS;
        }
    }

    function _d(uint256 x0, uint256 y) private pure returns (uint256) {
        unchecked {
            return y * y / _BASIS * 3 * x0 / _BASIS + x0 * x0 / _BASIS * x0 / _BASIS;
        }
    }

    function _get_y(uint256 x0, uint256 xy, uint256 y) private pure returns (uint256) {
        unchecked {
            for (uint256 i = 0; i < 255; i++) {
                uint256 y_prev = y;
                uint256 k = _f(x0, y);
                if (k < xy) {
                    uint256 dy = ((xy - k) * _BASIS) / _d(x0, y);
                    y = y + dy;
                } else {
                    uint256 dy = ((k - xy) * _BASIS) / _d(x0, y);
                    y = y - dy;
                }
                if (y > y_prev) {
                    if (y - y_prev <= 1) {
                        return y;
                    }
                } else {
                    if (y_prev - y <= 1) {
                        return y;
                    }
                }
            }
            return y;
        }
    }

    function sellToVelodrome(address recipient, uint256 bps, IVelodromePair pair, uint24 swapInfo, uint256 minAmountOut)
        internal
    {
        // Preventing calls to Permit2 or AH is not explicitly required as neither of these contracts implement the `swap` nor `transfer` selector

        // |7|6|5|4|3|2|1|0| - bit positions in swapInfo (uint8)
        // |0|0|0|0|0|0|F|Z| - Z: zeroForOne flag, F: sellTokenHasFee flag
        bool zeroForOne = (swapInfo & 1) == 1; // Extract the least significant bit (bit 0)
        bool sellTokenHasFee = (swapInfo & 2) >> 1 == 1; // Extract the second least significant bit (bit 1) and shift it right
        uint256 feeBps = swapInfo >> 8;

        (
            uint256 sellBasis,
            uint256 buyBasis,
            uint256 sellReserve,
            uint256 buyReserve,
            bool stable,
            IERC20 sellToken,
            IERC20 buyToken
        ) = pair.metadata();
        assert(stable);
        if (!zeroForOne) {
            (sellBasis, buyBasis, sellReserve, buyReserve, sellToken, buyToken) =
                (buyBasis, sellBasis, buyReserve, sellReserve, buyToken, sellToken);
        }

        uint256 buyAmount;
        unchecked {
            // Compute sell amount in native units
            uint256 sellAmount;
            if (bps != 0) {
                sellAmount = sellToken.balanceOf(address(this)) * bps / 10_000;
            }
            if (sellAmount != 0) {
                sellToken.safeTransfer(address(pair), sellAmount);
            }
            if (sellAmount == 0 || sellTokenHasFee) {
                sellAmount = sellToken.balanceOf(address(pair)) - sellReserve;
            }
            // Apply the fee
            sellAmount -= sellAmount * feeBps / 10_000;

            // Convert everything from native units to `_BASIS`
            sellReserve = (sellReserve * _BASIS).unsafeDiv(sellBasis);
            buyReserve = (buyReserve * _BASIS).unsafeDiv(buyBasis);
            sellAmount = (sellAmount * _BASIS).unsafeDiv(sellBasis);

            // Get current constant-function value
            uint256 xy = _k(sellReserve, buyReserve);

            // Solve the constant function to get `buyAmount` from `sellAmount`
            buyAmount = buyReserve - _get_y(sellAmount + sellReserve, xy, buyReserve);

            // Convert `buyAmount` from `_BASIS` to native units
            buyAmount = buyAmount * buyBasis / _BASIS;
        }
        if (buyAmount < minAmountOut) {
            revert TooMuchSlippage(sellToken, minAmountOut, buyAmount);
        }

        if (!zeroForOne) {
            pair.swap(buyAmount, 0, recipient, new bytes(0));
        } else {
            pair.swap(0, buyAmount, recipient, new bytes(0));
        }
    }
}
