// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

struct uint512 {
    uint256 hi;
    uint256 lo;
}

library Lib512Math {
    function from(uint512 memory r, uint256 x) internal pure {
        assembly ("memory-safe") {
            mstore(r, 0x00)
            mstore(add(0x20, r), x)
        }
    }

    function into(uint512 memory x) internal pure returns (uint256 r_hi, uint256 r_lo) {
        assembly ("memory-safe") {
            r_hi := mload(x)
            r_lo := mload(add(0x20, x))
        }
    }

    function _deallocate(uint512 memory r) private pure {
        assembly ("memory-safe") {
            let ptr := sub(mload(0x40), 0x40)
            if iszero(eq(ptr, r)) { revert(0x00, 0x00) }
            mstore(0x40, ptr)
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

    function odiv(uint512 memory r, uint512 memory x, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);

        // This function is mostly stolen from Remco Bloemen https://2π.com/21/muldiv/ .
        // The original code was released under the MIT license.
        assembly ("memory-safe") {
            let x_hi := mload(x)
            let x_lo := mload(add(0x20, x))

            // Get the remainder [x_hi x_lo] % y (< 2**256)
            // 2**256 % y == -y % 2**256 % y
            let rem := mulmod(x_hi, sub(0x00, y), y)
            rem := addmod(x_lo, rem, y)

            // Make division exact by rounding [x_hi x_lo] down to a multiple of y
            // Subtract 256 bit number from 512 bit number.
            x_hi := sub(x_hi, gt(rem, x_lo))
            x_lo := sub(x_lo, rem)

            // Factor powers of two out of denominator
            {
                // Compute largest power of two divisor of denominator
                // Always >= 1.
                let twos := and(sub(0x00, y), y)

                // Divide denominator by power of two
                y := div(y, twos)

                // Divide [x_hi x_lo] by the factors of two
                x_lo := div(x_lo, twos)
                // Shift in bits from x_hi into x_lo. For this we need to flip `twos`
                // such that it is 2**256 / twos.
                // 2**256 / twos == -twos % 2**256 / twos + 1
                // If twos is zero, then it becomes one
                let twosInv := add(div(sub(0x00, twos), twos), 0x01)
                x_lo := or(x_lo, mul(x_hi, twosInv))
                x_hi := div(x_hi, twos)
            }

            // Invert the denominator mod 2**512
            // Now that y is an odd number, it has an inverse modulo 2**512 such
            // that y * inv = 1 mod 2**512.
            // We use Newton-Raphson iterations compute inv.  Thanks to Hensel's
            // lifting lemma, this also works in modular arithmetic, doubling
            // the correct bits in each step. The Newton-Raphson-Hensel step is:
            //    inv_{n+1} = inv_n*(2-y*inv_n)

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
            //    inv_{n+1} = inv_n*(2-y*inv_n)
            function nrhStep(a_hi, a_lo, b) -> o_hi, o_lo {
                o_hi, o_lo := mul512x256(a_hi, a_lo, b)
                o_hi := sub(sub(0x00, o_hi), gt(o_lo, 0x02))
                o_lo := sub(0x02, o_lo)
                o_hi, o_lo := mul512x512(a_hi, a_lo, o_hi, o_lo)
            }

            // To kick off Newton-Raphson-Hensel iterations, we start with a
            // seed of the inverse that is correct correct for four bits. That
            // is, y * inv = 1 mod 2**4.
            let inv_hi, inv_lo := mul256x256(0x03, y)
            inv_lo := xor(0x02, inv_lo)

            // Each application of nrhStep doubles the number of correct bits in
            // inv. After 7 iterations, full convergence is guaranteed.
            // TODO: see if this is faster if the loop is re-rolled
            // TODO: can we go back to the "old", 256-bit version for all but the final step?
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2**8
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2**16
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2**32
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2**64
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2**128
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2**256
            inv_hi, inv_lo := nrhStep(inv_hi, inv_lo, y) // inverse mod 2**512

            // Because the division is now exact (we subtracted the remainder at
            // the beginning), we can divide by multiplying with the modular
            // inverse of the denominator. This will give us the correct result
            // modulo 2**512.
            let r_hi, r_lo := mul512x512(x_hi, x_lo, inv_hi, inv_lo)

            mstore(r, r_hi)
            mstore(add(0x20, r), r_lo)
            r_out := r
        }
    }

    function idiv(uint512 memory r, uint256 y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        r_out = odiv(r, r, y);
    }

    function odiv(uint512 memory r, uint512 memory x, uint512 memory y) internal pure returns (uint512 memory r_out) {
        _deallocate(r_out);
        revert("unimplemented");
    }

    function idiv(uint512 memory r, uint512 memory y) internal pure returns (uint512 memory r_out) {
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

function tmp_uint512() pure returns (uint512 memory r) {
    assembly ("memory-safe") {
        let ptr := sub(mload(0x40), 0x40)
        if iszero(eq(ptr, r)) { revert(0x00, 0x00) }
        mstore(0x40, ptr)

        r := 0x00
    }
}

using Lib512Math for uint512 global;
