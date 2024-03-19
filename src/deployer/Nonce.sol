// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev if you update this, you also have to update the length of the array `NonceList.List.links` in Deployer.sol
/// @dev if you update this, you also have to update the type in `ZeroExSettlerDeployerSafeModule.removeByNonceSelector` in SafeModule.sol
type Nonce is uint32;

function incr(Nonce a) pure returns (Nonce) {
    return Nonce.wrap(Nonce.unwrap(a) + 1);
}

function gt(Nonce a, Nonce b) pure returns (bool) {
    return Nonce.unwrap(a) > Nonce.unwrap(b);
}

function eq(Nonce a, Nonce b) pure returns (bool) {
    return Nonce.unwrap(a) == Nonce.unwrap(b);
}

function isNull(Nonce a) pure returns (bool) {
    return Nonce.unwrap(a) == 0;
}

using {incr, gt as >, eq as ==, isNull} for Nonce global;

Nonce constant zero = Nonce.wrap(0);
