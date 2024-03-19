// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Panic} from "../utils/Panic.sol";

/// @dev if you update this, you also have to update the type in `ZeroExSettlerDeployerSafeModule.remove` in SafeModule.sol
type Feature is uint128;

function eq(Feature a, Feature b) pure returns (bool) {
    return Feature.unwrap(a) == Feature.unwrap(b);
}

function isNull(Feature a) pure returns (bool) {
    return Feature.unwrap(a) == 0;
}

using {eq as ==, isNull} for Feature global;

function wrap(uint256 x) pure returns (Feature) {
    if (x > type(uint128).max) {
        Panic.panic(Panic.ARITHMETIC_OVERFLOW);
    }
    if (x == 0) {
        Panic.panic(Panic.ENUM_CAST);
    }
    return Feature.wrap(uint128(x));
}
