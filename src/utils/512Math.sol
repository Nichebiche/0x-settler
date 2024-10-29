// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Panic} from "./Panic.sol";

struct uint512 {
    uint256 hi;
    uint256 lo;
}

library Lib512Math {
    /// With optimization turned on, when used correctly, this function
    /// completely optimizes out and does not appear in the generated bytecode.
    function _deallocate(uint512 memory r) private pure {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            if iszero(eq(ptr, add(0x40, r))) { revert(0x00, 0x00) }
            mstore(0x40, r)
        }
    }

    function from(uint512 memory r, uint256 x) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            mstore(r, 0x00)
            mstore(add(0x20, r), x)
            r_out := r
        }
    }

    function from(uint512 memory r, uint256 x_hi, uint256 x_lo) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            mstore(r, x_hi)
            mstore(add(0x20, r), x_lo)
            r_out := r
        }
    }

    function from(uint512 memory r, uint512 memory x) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            // Paradoxically, using `mload` and `mstore` here produces more
            // optimal code because it gives solc the opportunity to
            // optimize-out the use of memory in typical usage. As a happy side
            // effect, it also means that we don't have to deal with Cancun
            // hardfork compatibility issues
            mstore(r, mload(x))
            mstore(add(0x20, r), mload(add(0x20, x)))
            r_out := r
        }
    }

    function into(uint512 memory x) internal pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            r_hi := mload(x)
            r_lo := mload(add(0x20, x))
        }
    }

    function oadd(uint512 memory r, uint256 x, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            let r_lo := add(x, y)
            let r_hi := lt(r_lo, x)

            mstore(r, r_hi)
            mstore(add(0x20, r), r_lo)
            r_out := r
        }
    }

    function oadd(uint512 memory r, uint512 memory x, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            let r_lo := add(x_lo, y)
            let r_hi := add(x_hi, lt(r_lo, x_lo))

            mstore(r, r_hi)
            mstore(add(0x20, r), r_lo)
            r_out := r
        }
    }

    function iadd(uint512 memory r, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = oadd(r, r, y);
    }

    function oadd(uint512 memory r, uint512 memory x, uint512 memory y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            let y_hi := mload(y)
            let y_lo := mload(add(0x20, y))
            let r_lo := add(x_lo, y_lo)
            let r_hi := add(add(x_hi, y_hi), lt(r_lo, x_lo))

            mstore(r, r_hi)
            mstore(add(0x20, r), r_lo)
            r_out := r
        }
    }

    function iadd(uint512 memory r, uint512 memory y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = oadd(r, r, y);
    }

    function osub(uint512 memory r, uint512 memory x, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            let r_lo := sub(x_lo, y)
            let r_hi := sub(x_hi, gt(y, x_lo))

            mstore(r, r_hi)
            mstore(add(0x20, r), r_lo)
            r_out := r
        }
    }

    function isub(uint512 memory r, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = osub(r, r, y);
    }

    function osub(uint512 memory r, uint512 memory x, uint512 memory y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            let y_hi := mload(y)
            let y_lo := mload(add(0x20, y))
            let r_lo := sub(x_lo, y_lo)
            let r_hi := sub(sub(x_hi, y_hi), gt(y_lo, x_lo))

            mstore(r, r_hi)
            mstore(add(0x20, r), r_lo)
            r_out := r
        }
    }

    function isub(uint512 memory r, uint512 memory y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = osub(r, r, y);
    }

    function omul(uint512 memory r, uint256 x, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            let mm := mulmod(x, y, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            let r_lo := mul(x, y)
            let r_hi := sub(sub(mm, r_lo), lt(mm, r_lo))

            mstore(r, r_hi)
            mstore(add(0x20, r), r_lo)
            r_out := r
        }
    }

    function omul(uint512 memory r, uint512 memory x, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            let mm := mulmod(x_lo, y, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            let r_lo := mul(x_lo, y)
            let r_hi := add(mul(x_hi, y), sub(sub(mm, r_lo), lt(mm, r_lo)))

            mstore(r, r_hi)
            mstore(add(0x20, r), r_lo)
            r_out := r
        }
    }

    function imul(uint512 memory r, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = omul(r, r, y);
    }

    function omul(uint512 memory r, uint512 memory x, uint512 memory y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            let y_hi := mload(y)
            let y_lo := mload(add(0x20, y))
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            let mm := mulmod(x_lo, y_lo, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
            let r_lo := mul(x_lo, y_lo)
            let r_hi := add(sub(sub(mm, r_lo), lt(mm, r_lo)), add(mul(x_hi, y_lo), mul(x_lo, y_hi)))

            mstore(r, r_hi)
            mstore(add(0x20, r), r_lo)
            r_out := r
        }
    }

    function imul(uint512 memory r, uint512 memory y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = omul(r, r, y);
    }

    function mod(uint512 memory n, uint256 d) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            let x_hi := mload(n)
            let x_lo := mload(add(0x20, n))
            r := mulmod(x_hi, sub(0x00, d), d)
            r := addmod(x_lo, r, d)
        }
    }

    function omod(uint512 memory r, uint512 memory x, uint512 memory y) internal view returns (uint512 memory r_out) {
        _deallocate(r_out);
        assembly ("memory-safe") {
            // We use the MODEXP (5) precompile with an exponent of 1. We encode
            // the arguments to the precompile at the beginning of free memory
            // without allocating. Conveniently, r_out already points to this
            // memory region. Arguments are encoded as:
            //     [64 32 64 x_hi x_lo 1 y_hi y_lo]
            mstore(r_out, 0x40)
            mstore(add(0x20, r_out), 0x20)
            mstore(add(0x40, r_out), 0x40)
            // See comment in `from` about why `mload`/`mstore` is more efficient
            mstore(add(0x60, r_out), mload(x))
            mstore(add(0x80, r_out), mload(add(0x20, x)))
            mstore(add(0xa0, r_out), 0x01)
            mstore(add(0xc0, r_out), mload(y))
            mstore(add(0xe0, r_out), mload(add(0x20, y)))
            // We write the result of MODEXP directly into the output space r.
            // The MODEXP precompile can only fail due to out-of-gas.
            // There is no returndata in the event of failure.
            if or(iszero(returndatasize()), iszero(staticcall(gas(), 0x05, r_out, 0x100, r, 0x40))) {
                revert(0x00, 0x00)
            }

            r_out := r
        }
    }

    function imod(uint512 memory r, uint512 memory y) internal view returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = omod(r, r, y);
    }

    function _roundDown(uint256 x_hi, uint256 x_lo, uint256 d) private pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            // Get the remainder [n_hi n_lo] % d (< 2²⁵⁶)
            // 2**256 % d = -d % 2**256 % d
            let rem := mulmod(x_hi, sub(0x00, d), d)
            rem := addmod(x_lo, rem, d)

            r_hi := sub(x_hi, gt(rem, x_lo))
            r_lo := sub(x_lo, rem)
        }
    }

    function _roundDown(uint256 x_hi, uint256 x_lo, uint256 d_hi, uint256 d_lo) private view returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            // Get the remainder [x_hi x_lo] % [d_hi d_lo] (< 2⁵¹²)
            // We use the MODEXP (5) precompile with an exponent of 1. We encode
            // the arguments to the precompile at the beginning of free memory
            // without allocating. Arguments are encoded as:
            //     [64 32 64 x_hi x_lo 1 d_hi d_lo]
            let ptr := mload(0x40)
            mstore(ptr, 0x40)
            mstore(add(0x20, ptr), 0x20)
            mstore(add(0x40, ptr), 0x40)
            mstore(add(0x60, ptr), x_hi)
            mstore(add(0x80, ptr), x_lo)
            mstore(add(0xa0, ptr), 0x01)
            mstore(add(0xc0, ptr), d_hi)
            mstore(add(0xe0, ptr), d_lo)
            // The MODEXP precompile can only fail due to out-of-gas.
            // There is no returndata in the event of failure.
            if or(iszero(returndatasize()), iszero(staticcall(gas(), 0x05, ptr, 0x100, ptr, 0x40))) {
                revert(0x00, 0x00)
            }

            let rem_hi := mload(ptr)
            let rem_lo := mload(add(0x20, ptr))
            // Round down by subtracting the remainder from the numerator
            // Subtract 512-bit number from 512-bit number.
            r_hi := sub(sub(x_hi, rem_hi), gt(rem_lo, x_lo))
            r_lo := sub(x_lo, rem_lo)
        }
    }

    function div(uint512 memory n, uint256 d) internal pure returns (uint256 q) {
        if (d == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        uint256 n_hi;
        uint256 n_lo;
        assembly ("memory-safe") {
            n_hi := mload(n)
            n_lo := mload(add(0x20, n))
        }
        if (n_hi == 0) {
            assembly ("memory-safe") {
                q := div(n_lo, d)
            }
            return q;
        }

        // Round the numerator down to a multiple of the denominator. This makes
        // the division exact without affecting the result.
        (n_hi, n_lo) = _roundDown(n_hi, n_lo, d);

        // This function is mostly stolen from Remco Bloemen https://2π.com/21/muldiv/ .
        // The original code was released under the MIT license.
        assembly ("memory-safe") {
            // Factor powers of two out of the denominator
            {
                // Compute largest power of two divisor of the denominator
                // Always ≥ 1.
                let twos := and(sub(0x00, d), d)

                // Divide d by the power of two
                d := div(d, twos)

                // Divide [n_hi n_lo] by the power of two
                n_lo := div(n_lo, twos)
                // Shift in bits from n_hi into n_lo. For this we need to flip `twos`
                // such that it is 2²⁵⁶ / twos.
                //     2**256 / twos = -twos % 2**256 / twos + 1
                // If twos is zero, then it becomes one (not possible)
                let twosInv := add(div(sub(0x00, twos), twos), 0x01)
                n_lo := or(n_lo, mul(n_hi, twosInv))
            }

            // Invert the denominator mod 2²⁵⁶
            // Now that d is an odd number, it has an inverse modulo 2²⁵⁶ such
            // that d * inv ≡ 1 mod 2²⁵⁶.
            // We use Newton-Raphson iterations compute inv. Thanks to Hensel's
            // lifting lemma, this also works in modular arithmetic, doubling
            // the correct bits in each step. The Newton-Raphson-Hensel step is:
            //    inv_{n+1} = inv_n * (2 - d*inv_n) % 2**512

            // To kick off Newton-Raphson-Hensel iterations, we start with a
            // seed of the inverse that is correct correct for four bits.
            //     d * inv ≡ 1 mod 2⁴
            let inv := xor(mul(0x03, d), 0x02)

            // Each Newton-Raphson-Hensel step doubles the number of correct
            // bits in inv. After 6 iterations, full convergence is guaranteed.
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2⁸
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2¹⁶
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2³²
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2⁶⁴
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2¹²⁸
            inv := mul(inv, sub(0x02, mul(d, inv))) // inverse mod 2²⁵⁶

            // Because the division is now exact (we subtracted the remainder at
            // the beginning), we can divide by multiplying with the modular
            // inverse of the denominator. This will give us the correct result
            // modulo 2²⁵⁶.
            q := mul(n_lo, inv)
        }
    }

    function div(uint512 memory n, uint512 memory d) internal view returns (uint256 q) {
        (uint256 d_hi, uint256 d_lo) = (d.hi, d.lo);
        if (d_hi == 0) {
            return div(n, d_lo);
        }

        uint256 n_hi;
        assembly ("memory-safe") {
            n_hi := mload(n)
        }
        if (d_lo == 0) {
            assembly ("memory-safe") {
                q := div(n_hi, d_hi)
            }
            return q;
        }
        if (n_hi == 0) {
            // TODO: this optimization may not be overall optimizing
            return q; // zero
        }
        uint256 n_lo;
        assembly ("memory-safe") {
            n_lo := mload(add(0x20, n))
        }

        // Round the numerator down to a multiple of the denominator. This makes
        // the division exact without affecting the result.
        (n_hi, n_lo) = _roundDown(n_hi, n_lo, d_hi, d_lo);


        // This function is mostly stolen from Remco Bloemen https://2π.com/21/muldiv/ .
        // The original code was released under the MIT license.
        assembly ("memory-safe") {
            // Factor powers of two out of the denominator
            {
                // Compute largest power of two divisor of the denominator
                // d_lo is nonzero, so this is always ≥1.
                let twos := and(sub(0x00, d_lo), d_lo)
                // Shift in bits from n_hi into n_lo and from d_hi into
                // d_lo. For this we need to flip `twos` such that it is
                // 2²⁵⁶ / twos.
                //     2**256 / twos = -twos % 2**256 / twos + 1
                // If twos is zero, then it becomes one (not possible)
                let twosInv := add(div(sub(0x00, twos), twos), 0x01)

                // Divide [d_hi d_lo] by the power of two
                d_lo := div(d_lo, twos)
                d_lo := or(d_lo, mul(d_hi, twosInv))
                // Our result is only 256 bits, so we can discard d_hi after this

                // Divide [n_hi n_lo] by the power of two
                n_lo := div(n_lo, twos)
                n_lo := or(n_lo, mul(n_hi, twosInv))
                // Our result is only 256 bits, so we can discard n_hi after this
            }

            // Invert the denominator mod 2²⁵⁶
            // Now that d_lo is an odd number, it has an inverse modulo 2²⁵⁶ such
            // that d_lo * inv ≡ 1 mod 2²⁵⁶.
            // We use Newton-Raphson iterations compute inv. Thanks to Hensel's
            // lifting lemma, this also works in modular arithmetic, doubling
            // the correct bits in each step. The Newton-Raphson-Hensel step is:
            //    inv_{n+1} = inv_n * (2 - d_lo*inv_n) % 2**512

            // To kick off Newton-Raphson-Hensel iterations, we start with a
            // seed of the inverse that is correct correct for four bits.
            //     d_lo * inv ≡ 1 mod 2⁴
            let inv := xor(mul(0x03, d_lo), 0x02)

            // Each Newton-Raphson-Hensel step doubles the number of correct
            // bits in inv. After 6 iterations, full convergence is guaranteed.
            inv := mul(inv, sub(0x02, mul(d_lo, inv))) // inverse mod 2⁸
            inv := mul(inv, sub(0x02, mul(d_lo, inv))) // inverse mod 2¹⁶
            inv := mul(inv, sub(0x02, mul(d_lo, inv))) // inverse mod 2³²
            inv := mul(inv, sub(0x02, mul(d_lo, inv))) // inverse mod 2⁶⁴
            inv := mul(inv, sub(0x02, mul(d_lo, inv))) // inverse mod 2¹²⁸
            inv := mul(inv, sub(0x02, mul(d_lo, inv))) // inverse mod 2²⁵⁶

            // Because the division is now exact (we subtracted the remainder at
            // the beginning), we can divide by multiplying with the modular
            // inverse of the denominator. This will give us the correct result
            // modulo 2²⁵⁶.
            q := mul(n_lo, inv)
        }
    }

    function odiv(uint512 memory r, uint512 memory x, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);

        if (y == 0) {
            Panic.panic(Panic.DIVISION_BY_ZERO);
        }

        uint256 x_hi;
        uint256 x_lo;
        assembly ("memory-safe") {
            x_hi := mload(x)
            x_lo := mload(add(0x20, x))
        }
        if (x_hi == 0) {
            assembly ("memory-safe") {
                let r_lo := div(x_lo, y)
                mstore(r, 0x00)
                mstore(add(0x20, r), r_lo)
                r_out := r
            }
            return r_out;
        }

        // Round the numerator down to a multiple of the denominator. This makes
        // the division exact without affecting the result.
        (x_hi, x_lo) = _roundDown(x_hi, x_lo, y);

        // This function is mostly stolen from Remco Bloemen https://2π.com/21/muldiv/ .
        // The original code was released under the MIT license.
        assembly ("memory-safe") {
            // Factor powers of two out of the denominator
            {
                // Compute largest power of two divisor of the denominator
                // Always ≥ 1.
                let twos := and(sub(0x00, y), y)

                // Divide y by the power of two
                y := div(y, twos)

                // Divide [x_hi x_lo] by the power of two
                x_lo := div(x_lo, twos)
                // Shift in bits from x_hi into x_lo. For this we need to flip `twos`
                // such that it is 2²⁵⁶ / twos.
                //     2**256 / twos = -twos % 2**256 / twos + 1
                // If twos is zero, then it becomes one (not possible)
                let twosInv := add(div(sub(0x00, twos), twos), 0x01)
                x_lo := or(x_lo, mul(x_hi, twosInv))
                x_hi := div(x_hi, twos)
            }

            // Invert the denominator mod 2⁵¹²
            // Now that y is an odd number, it has an inverse modulo 2⁵¹² such
            // that y * inv ≡ 1 mod 2⁵¹².
            // We use Newton-Raphson iterations compute inv. Thanks to Hensel's
            // lifting lemma, this also works in modular arithmetic, doubling
            // the correct bits in each step. The Newton-Raphson-Hensel step is:
            //    inv_{n+1} = inv_n * (2 - y*inv_n) % 2**512

            // These are pure-Yul reimplementations of the corresponding
            // functions above. They're needed here as helper functions for
            // nrhStep.
            function mul256x256(a, b) -> o_hi, o_lo {
                let mm := mulmod(a, b, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
                o_lo := mul(a, b)
                o_hi := sub(sub(mm, o_lo), lt(mm, o_lo))
            }

            function mul512x256(a_hi, a_lo, b) -> o_hi, o_lo {
                o_hi, o_lo := mul256x256(a_lo, b)
                o_hi := add(mul(a_hi, b), o_hi)
            }

            function mul512x512(a_hi, a_lo, b_hi, b_lo) -> o_hi, o_lo {
                o_hi, o_lo := mul512x256(a_hi, a_lo, b_lo)
                o_hi := add(mul(a_lo, b_hi), o_hi)
            }

            // This is the Newton-Raphson-Hensel step:
            //    inv_{n+1} = inv_n * (2 - y*inv_n) % 2**512
            function nrhStep(a_hi, a_lo, b) -> o_hi, o_lo {
                o_hi, o_lo := mul512x256(a_hi, a_lo, b)
                o_hi := sub(sub(0x00, o_hi), gt(o_lo, 0x02))
                o_lo := sub(0x02, o_lo)
                o_hi, o_lo := mul512x512(a_hi, a_lo, o_hi, o_lo)
            }

            // To kick off Newton-Raphson-Hensel iterations, we start with a
            // seed of the inverse that is correct correct for four bits.
            //     y * inv ≡ 1 mod 2⁴
            let inv_hi, inv_lo := mul256x256(0x03, y)
            inv_lo := xor(0x02, inv_lo)

            // Each application of nrhStep doubles the number of correct bits in
            // inv. After 7 iterations, full convergence is guaranteed.
            // TODO: see if this is faster if the loop is re-rolled
            // TODO: can we go back to the "old", 256-bit version for all but the final step?
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2⁸
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2¹⁶
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2³²
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2⁶⁴
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2¹²⁸
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2²⁵⁶
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2⁵¹²

            // Because the division is now exact (we subtracted the remainder at
            // the beginning), we can divide by multiplying with the modular
            // inverse of the denominator. This will give us the correct result
            // modulo 2⁵¹².
            {
                let r_hi, r_lo := mul512x512(x_hi, x_lo, inv_hi, inv_lo)

                mstore(r, r_hi)
                mstore(add(0x20, r), r_lo)
            }
            r_out := r
        }
    }

    function idiv(uint512 memory r, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = odiv(r, r, y);
    }

    function odiv(uint512 memory r, uint512 memory x, uint512 memory y) internal view returns (uint512 memory r_out) {
        _deallocate(r_out);
        (uint256 y_hi, uint256 y_lo) = (y.hi, y.lo);
        if (y_hi == 0) {
            return odiv(r, x, y_lo);
        }

        // This function is mostly stolen from Remco Bloemen https://2π.com/21/muldiv/ .
        // The original code was released under the MIT license.
        assembly ("memory-safe") {
            for {} 1 {} {
                let x_hi := mload(x)

                if iszero(y_lo) {
                    let r_lo := div(x_hi, y_hi)
                    mstore(r, 0x00)
                    mstore(add(0x20, r), r_lo)
                    break
                }

                let x_lo := mload(add(0x20, x))

                // TODO: this optimization may not be overall optimizing
                if iszero(x_hi) {
                    codecopy(r, codesize(), 0x40)
                    break
                }

                // Subtract the remainder from the numerator so that it is a
                // multiple of the denominator. This makes the division exact
                {
                    // Get the remainder [x_hi x_lo] % [y_hi y_lo] (< 2⁵¹²) We
                    // use the MODEXP (5) precompile with an exponent of 1.  We
                    // encode the arguments to the precompile at the beginning
                    // of free memory without allocating. Conveniently, r_out
                    // already points to this memory region. Arguments are
                    // encoded as:
                    //     [64 32 64 x_hi x_lo 1 y_hi y_lo]
                    mstore(r_out, 0x40)
                    mstore(add(0x20, r_out), 0x20)
                    mstore(add(0x40, r_out), 0x40)
                    mcopy(add(0x60, r_out), x, 0x40)
                    mstore(add(0xa0, r_out), 0x01)
                    mcopy(add(0xc0, r_out), y, 0x40)
                    // The MODEXP precompile can only fail due to out-of-gas.
                    // There is no returndata in the event of failure.
                    if or(iszero(returndatasize()), iszero(staticcall(gas(), 0x05, r_out, 0x100, r_out, 0x40))) {
                        revert(0x00, 0x00)
                    }
                    let rem_hi := mload(r_out)
                    let rem_lo := mload(add(0x20, r_out))

                    // Make division exact by rounding [x_hi x_lo] down to a
                    // multiple of [y_hi y_lo]
                    // Subtract 512-bit number from 512-bit number.
                    x_hi := sub(sub(x_hi, rem_hi), gt(rem_lo, x_lo))
                    x_lo := sub(x_lo, rem_lo)
                }

                // Factor powers of two out of the denominator
                {
                    // Compute largest power of two divisor of the denominator
                    // y_lo is nonzero, so this is always ≥1.
                    let twos := and(sub(0x00, y_lo), y_lo)
                    // Shift in bits from x_hi into x_lo and from y_hi into
                    // y_lo. For this we need to flip `twos` such that it is
                    // 2²⁵⁶ / twos.
                    //     2**256 / twos = -twos % 2**256 / twos + 1
                    // If twos is zero, then it becomes one (not possible)
                    let twosInv := add(div(sub(0x00, twos), twos), 0x01)

                    // Divide [y_hi y_lo] by the power of two
                    y_lo := div(y_lo, twos)
                    y_lo := or(y_lo, mul(y_hi, twosInv))
                    y_hi := div(y_hi, twos)

                    // Divide [x_hi x_lo] by the power of two
                    x_lo := div(x_lo, twos)
                    x_lo := or(x_lo, mul(x_hi, twosInv))
                    x_hi := div(x_hi, twos)
                }

                // Invert the denominator mod 2⁵¹²
                // Now that [y_hi y_lo] is an odd number, it has an inverse
                // modulo 2⁵¹² such that y * inv ≡ 1 mod 2⁵¹².
                // We use Newton-Raphson iterations compute inv. Thanks to
                // Hensel's lifting lemma, this also works in modular
                // arithmetic, doubling the correct bits in each step. The
                // Newton-Raphson-Hensel step is:
                //    inv_{n+1} = inv_n * (2 - y*inv_n) % 2**512

                // These are pure-Yul reimplementations of the corresponding
                // functions above. They're needed here as helper functions for
                // nrhStep.
                // TODO: this function is unused, factor it into mul512x256
                function mul256x256(a, b) -> o_hi, o_lo {
                    let mm := mulmod(a, b, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
                    o_lo := mul(a, b)
                    o_hi := sub(sub(mm, o_lo), lt(mm, o_lo))
                }

                function mul512x256(a_hi, a_lo, b) -> o_hi, o_lo {
                    o_hi, o_lo := mul256x256(a_lo, b)
                    o_hi := add(mul(a_hi, b), o_hi)
                }

                function mul512x512(a_hi, a_lo, b_hi, b_lo) -> o_hi, o_lo {
                    o_hi, o_lo := mul512x256(a_hi, a_lo, b_lo)
                    o_hi := add(mul(a_lo, b_hi), o_hi)
                }

                // This is the Newton-Raphson-Hensel step:
                //    inv_{n+1} = inv_n * (2 - y*inv_n) % 2**512
                function nrhStep(a_hi, a_lo, b_hi, b_lo) -> o_hi, o_lo {
                    o_hi, o_lo := mul512x512(a_hi, a_lo, b_hi, b_lo)
                    o_hi := sub(sub(0x00, o_hi), gt(o_lo, 0x02))
                    o_lo := sub(0x02, o_lo)
                    o_hi, o_lo := mul512x512(a_hi, a_lo, o_hi, o_lo)
                }

                // To kick off Newton-Raphson-Hensel iterations, we start with a
                // seed of the inverse that is correct correct for four bits.
                //     y * inv ≡ 1 mod 2⁴
                let inv_hi, inv_lo := mul512x256(y_hi, y_lo, 0x03)
                inv_lo := xor(0x02, inv_lo)

                // Each application of nrhStep doubles the number of correct
                // bits in inv. After 7 iterations, full convergence is
                // guaranteed.
                // TODO: see if this is faster if the loop is re-rolled
                // TODO: can we go back to the "old", 256-bit version for all but the final step?
                inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y_hi, y_lo) // inverse mod 2⁸
                inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y_hi, y_lo) // inverse mod 2¹⁶
                inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y_hi, y_lo) // inverse mod 2³²
                inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y_hi, y_lo) // inverse mod 2⁶⁴
                inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y_hi, y_lo) // inverse mod 2¹²⁸
                inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y_hi, y_lo) // inverse mod 2²⁵⁶
                inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y_hi, y_lo) // inverse mod 2⁵¹²

                // Because the division is now exact (we subtracted the
                // remainder at the beginning), we can divide by multiplying
                // with the modular inverse of the denominator. This will give
                // us the correct result modulo 2⁵¹².
                {
                    let r_hi, r_lo := mul512x512(x_hi, x_lo, inv_hi, inv_lo)

                    mstore(r, r_hi)
                    mstore(add(0x20, r), r_lo)
                }
                break
            }
            r_out := r
        }
    }

    function idiv(uint512 memory r, uint512 memory y) internal view returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = odiv(r, r, y);
    }

    function eq(uint512 memory x, uint256 y) internal pure returns (bool r) {
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            r := and(iszero(x_hi), eq(x_lo, y))
        }
    }

    function gt(uint512 memory x, uint256 y) internal pure returns (bool r) {
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            r := or(gt(x_hi, 0x00), gt(x_lo, y))
        }
    }

    function lt(uint512 memory x, uint256 y) internal pure returns (bool r) {
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            r := and(iszero(x_hi), lt(x_lo, y))
        }
    }

    function ne(uint512 memory x, uint256 y) internal pure returns (bool) {
        return !eq(x, y);
    }

    function ge(uint512 memory x, uint256 y) internal pure returns (bool) {
        return !lt(x, y);
    }

    function le(uint512 memory x, uint256 y) internal pure returns (bool) {
        return !gt(x, y);
    }

    function eq(uint512 memory x, uint512 memory y) internal pure returns (bool r) {
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            let y_hi := mload(y)
            let y_lo := mload(add(0x20, y))
            r := and(eq(x_hi, y_hi), eq(x_lo, y_lo))
        }
    }

    function gt(uint512 memory x, uint512 memory y) internal pure returns (bool r) {
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            let y_hi := mload(y)
            let y_lo := mload(add(0x20, y))
            r := or(gt(x_hi, y_hi), and(eq(x_hi, y_hi), gt(x_lo, y_lo)))
        }
    }

    function lt(uint512 memory x, uint512 memory y) internal pure returns (bool r) {
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))
            let y_hi := mload(y)
            let y_lo := mload(add(0x20, y))
            r := or(lt(x_hi, y_hi), and(eq(x_hi, y_hi), lt(x_lo, y_lo)))
        }
    }

    function ne(uint512 memory x, uint512 memory y) internal pure returns (bool) {
        return !eq(x, y);
    }

    function ge(uint512 memory x, uint512 memory y) internal pure returns (bool) {
        return !lt(x, y);
    }

    function le(uint512 memory x, uint512 memory y) internal pure returns (bool) {
        return !gt(x, y);
    }
}

function tmp() pure returns (uint512 memory r) {
    assembly ("memory-safe") {
        let ptr := sub(mload(0x40), 0x40)
        if iszero(eq(ptr, r)) { revert(0x00, 0x00) }
        mstore(0x40, ptr)

        r := 0x00
    }
}

using Lib512Math for uint512 global;
