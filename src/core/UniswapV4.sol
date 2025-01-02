// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {ISignatureTransfer} from "@permit2/interfaces/ISignatureTransfer.sol";
import {SafeTransferLib} from "../vendor/SafeTransferLib.sol";
import {SettlerAbstract} from "../SettlerAbstract.sol";

import {Panic} from "../utils/Panic.sol";
import {UnsafeMath} from "../utils/UnsafeMath.sol";

import {
    TooMuchSlippage,
    DeltaNotPositive,
    DeltaNotNegative,
    ZeroSellAmount,
    ZeroBuyAmount,
    BoughtSellToken,
    TokenHashCollision,
    ZeroToken
} from "./SettlerErrors.sol";

import {
    BalanceDelta, IHooks, IPoolManager, UnsafePoolManager, POOL_MANAGER, IUnlockCallback
} from "./UniswapV4Types.sol";
import {Encoder, NotesLib, StateLib, Decoder} from "./FlashAccountingCommon.sol";

library CreditDebt {
    using UnsafeMath for int256;

    function asCredit(int256 delta, IERC20 token) internal pure returns (uint256) {
        if (delta < 0) {
            revert DeltaNotPositive(token);
        }
        return uint256(delta);
    }

    function asDebt(int256 delta, IERC20 token) internal pure returns (uint256) {
        if (delta > 0) {
            revert DeltaNotNegative(token);
        }
        return uint256(delta.unsafeNeg());
    }
}

abstract contract UniswapV4 is SettlerAbstract {
    using SafeTransferLib for IERC20;
    using UnsafeMath for uint256;
    using UnsafeMath for int256;
    using CreditDebt for int256;
    using UnsafePoolManager for IPoolManager;
    using NotesLib for NotesLib.Note;
    using NotesLib for NotesLib.Note[];
    using StateLib for StateLib.State;

    constructor() {
        assert(BASIS == Decoder.BASIS);
        assert(ETH_ADDRESS == Decoder.ETH_ADDRESS);
    }

    //// These two functions are the entrypoints to this set of actions. Because UniV4 has a
    //// mandatory callback, and the vast majority of the business logic has to be executed inside
    //// the callback, they're pretty minimal. Both end up inside the last function in this file
    //// `unlockCallback`, which is where most of the business logic lives. Primarily, these
    //// functions are concerned with correctly encoding the argument to
    //// `POOL_MANAGER.unlock(...)`. Pay special attention to the `payer` field, which is what
    //// signals to the callback whether we should be spending a coupon.

    //// How to generate `fills` for UniV4:
    ////
    //// Linearize your DAG of fills by doing a topological sort on the tokens involved. In the
    //// topological sort of tokens, when there is a choice of the next token, break ties by
    //// preferring a token if it is the lexicographically largest token that is bought among fills
    //// with sell token equal to the previous token in the topological sort. Then sort the fills
    //// belonging to each sell token by their buy token. This technique isn't *quite* optimal, but
    //// it's pretty close. The buy token of the final fill is special-cased. It is the token that
    //// will be transferred to `recipient` and have its slippage checked against `amountOutMin`. In
    //// the event that you are encoding a series of fills with more than one output token, ensure
    //// that at least one of the global buy token's fills is positioned appropriately.
    ////
    //// Now that you have a list of fills, encode each fill as follows.
    //// First encode the `bps` for the fill as 2 bytes. Remember that this `bps` is relative to the
    //// running balance at the moment that the fill is settled.
    //// Second, encode the packing key for that fill as 1 byte. The packing key byte depends on the
    //// tokens involved in the previous fill. The packing key for the first fill must be 1;
    //// i.e. encode only the buy token for the first fill.
    ////   0 -> sell and buy tokens remain unchanged from the previous fill (pure multiplex)
    ////   1 -> sell token remains unchanged from the previous fill, buy token is encoded (diamond multiplex)
    ////   2 -> sell token becomes the buy token from the previous fill, new buy token is encoded (multihop)
    ////   3 -> both sell and buy token are encoded
    //// Obviously, after encoding the packing key, you encode 0, 1, or 2 tokens (each as 20 bytes),
    //// as appropriate.
    //// The remaining fields of the fill are mandatory.
    //// Third, encode the pool fee as 3 bytes, and the pool tick spacing as 3 bytes.
    //// Fourth, encode the hook address as 20 bytes.
    //// Fifth, encode the hook data for the fill. Encode the length of the hook data as 3 bytes,
    //// then append the hook data itself.
    ////
    //// Repeat the process for each fill and concatenate the results without padding.

    function sellToUniswapV4(
        address recipient,
        IERC20 sellToken,
        uint256 bps,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        uint256 amountOutMin
    ) internal returns (uint256 buyAmount) {
        if (bps > BASIS) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        bytes memory data = Encoder.encode(uint32(IPoolManager.unlock.selector), recipient, sellToken, bps, feeOnTransfer, hashMul, hashMod, fills, amountOutMin);
        bytes memory encodedBuyAmount = _setOperatorAndCall(
            address(POOL_MANAGER), data, uint32(IUnlockCallback.unlockCallback.selector), _uniV4Callback
        );
        // buyAmount = abi.decode(abi.decode(encodedBuyAmount, (bytes)), (uint256));
        assembly ("memory-safe") {
            // We can skip all the checks performed by `abi.decode` because we know that this is the
            // verbatim result from `unlockCallback` and that `unlockCallback` encoded the buy
            // amount correctly.
            buyAmount := mload(add(0x60, encodedBuyAmount))
        }
    }

    function sellToUniswapV4VIP(
        address recipient,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 amountOutMin
    ) internal returns (uint256 buyAmount) {
        bytes memory data = Encoder.encodeVIP(uint32(IPoolManager.unlock.selector), recipient, feeOnTransfer, hashMul, hashMod, fills, permit, sig, _isForwarded(), amountOutMin);
        bytes memory encodedBuyAmount = _setOperatorAndCall(
            address(POOL_MANAGER), data, uint32(IUnlockCallback.unlockCallback.selector), _uniV4Callback
        );
        // buyAmount = abi.decode(abi.decode(encodedBuyAmount, (bytes)), (uint256));
        assembly ("memory-safe") {
            // We can skip all the checks performed by `abi.decode` because we know that this is the
            // verbatim result from `unlockCallback` and that `unlockCallback` encoded the buy
            // amount correctly.
            buyAmount := mload(add(0x60, encodedBuyAmount))
        }
    }

    function _uniV4Callback(bytes calldata data) private returns (bytes memory) {
        // We know that our calldata is well-formed. Therefore, the first slot is 0x20 and the
        // second slot is the length of the strict ABIEncoded payload
        assembly ("memory-safe") {
            data.length := calldataload(add(0x20, data.offset))
            data.offset := add(0x40, data.offset)
        }
        return unlockCallback(data);
    }

    //// The following functions are the helper functions for `unlockCallback`. They abstract much
    //// of the complexity of tracking which tokens need to be zeroed out at the end of the
    //// callback.
    ////
    //// The two major pieces of state that are maintained through the callback are `Note[] memory
    //// notes` and `State memory state`
    ////
    //// `notes` keeps track of the list of the tokens that have been touched throughout the
    //// callback that have nonzero credit. At the end of the fills, all tokens with credit will be
    //// swept back to Settler. These are the global buy token (against which slippage is checked)
    //// and any other multiplex-out tokens. Only the global sell token is allowed to have debt, but
    //// it is accounted slightly differently from the other tokens. The function `_take` is
    //// responsible for iterating over the list of tokens and withdrawing any credit to the
    //// appropriate recipient.
    ////
    //// `state` exists to reduce stack pressure and to simplify/gas-optimize the process of
    //// swapping. By keeping track of the sell and buy token on each hop, we're able to compress
    //// the representation of the fills required to satisfy the swap. Most often in a swap, the
    //// tokens in adjacent fills are somewhat in common. By caching, we avoid having them appear
    //// multiple times in the calldata.

    // the mandatory fields are
    // 2 - sell bps
    // 1 - pool key tokens case
    // 3 - pool fee
    // 3 - pool tick spacing
    // 20 - pool hooks
    // 3 - hook data length
    uint256 private constant _HOP_DATA_LENGTH = 32;

    uint256 private constant _ADDRESS_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

    /// Decode a `PoolKey` from its packed representation in `bytes` and the token information in
    /// `state`. Returns the `zeroForOne` flag and the suffix of the bytes that are not consumed in
    /// the decoding process.
    function _setPoolKey(IPoolManager.PoolKey memory key, StateLib.State memory state, bytes calldata data)
        private
        pure
        returns (bool, bytes calldata)
    {
        (IERC20 sellToken, IERC20 buyToken) = (state.sell.token, state.buy.token);
        bool zeroForOne;
        assembly ("memory-safe") {
            sellToken := and(_ADDRESS_MASK, sellToken)
            buyToken := and(_ADDRESS_MASK, buyToken)
            zeroForOne :=
                or(
                    eq(sellToken, 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee),
                    and(iszero(eq(buyToken, 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee)), lt(sellToken, buyToken))
                )
        }
        (key.token0, key.token1) = zeroForOne ? (sellToken, buyToken) : (buyToken, sellToken);

        uint256 packed;
        assembly ("memory-safe") {
            packed := shr(0x30, calldataload(data.offset))

            data.offset := add(0x1a, data.offset)
            data.length := sub(data.length, 0x1a)
            // we don't check for array out-of-bounds here; we will check it later in `_getHookData`
        }

        key.fee = uint24(packed >> 184);
        key.tickSpacing = int24(uint24(packed >> 160));
        key.hooks = IHooks.wrap(address(uint160(packed)));

        return (zeroForOne, data);
    }

    /// `_take` is responsible for removing the accumulated credit in each token from the pool
    /// manager. The current `state.buy` is the global buy token. We return the settled amount of
    /// that token (`buyAmount`), after checking it against the slippage limit
    /// (`minBuyAmount`). Each token with credit causes a corresponding call to `POOL_MANAGER.take`.
    function _take(StateLib.State memory state, NotesLib.Note[] memory notes, address recipient, uint256 minBuyAmount)
        private
        returns (uint256 buyAmount)
    {
        notes.del(state.buy);
        if (state.sell.amount == 0) {
            notes.del(state.sell);
        }

        uint256 length = notes.length;
        // `length` of zero implies that we fully liquidated the global sell token (there is no
        // `amount` remaining) and that the only token in which we have credit is the global buy
        // token. We're about to `take` that token below.
        if (length != 0) {
            {
                NotesLib.Note memory firstNote = notes[0]; // out-of-bounds is impossible
                if (!firstNote.eq(state.globalSell)) {
                    // The global sell token being in a position other than the 1st would imply that
                    // at some point we _bought_ that token. This is illegal and results in a revert
                    // with reason `BoughtSellToken(address)`.
                    IPoolManager(msg.sender).unsafeTake(firstNote.token, address(this), firstNote.amount);
                }
            }
            for (uint256 i = 1; i < length; i = i.unsafeInc()) {
                (IERC20 token, uint256 amount) = notes.unsafeGet(i);
                IPoolManager(msg.sender).unsafeTake(token, address(this), amount);
            }
        }

        // The final token to be bought is considered the global buy token. We bypass `notes` and
        // read it directly from `state`. Check the slippage limit. Transfer to the recipient.
        {
            IERC20 buyToken = state.buy.token;
            buyAmount = state.buy.amount;
            if (buyAmount < minBuyAmount) {
                revert TooMuchSlippage(buyToken, minBuyAmount, buyAmount);
            }
            IPoolManager(msg.sender).unsafeTake(buyToken, recipient, buyAmount);
        }
    }

    function _pay(
        IERC20 sellToken,
        address payer,
        uint256 sellAmount,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bool isForwarded,
        bytes calldata sig
    ) private returns (uint256) {
        IPoolManager(msg.sender).unsafeSync(sellToken);
        if (payer == address(this)) {
            sellToken.safeTransfer(msg.sender, sellAmount);
        } else {
            // assert(payer == address(0));
            ISignatureTransfer.SignatureTransferDetails memory transferDetails =
                ISignatureTransfer.SignatureTransferDetails({to: msg.sender, requestedAmount: sellAmount});
            _transferFrom(permit, transferDetails, sig, isForwarded);
        }
        return IPoolManager(msg.sender).unsafeSettle();
    }

    function unlockCallback(bytes calldata data) private returns (bytes memory) {
        address recipient;
        uint256 minBuyAmount;
        uint256 hashMul;
        uint256 hashMod;
        bool feeOnTransfer;
        address payer;
        (data, recipient, minBuyAmount, hashMul, hashMod, feeOnTransfer, payer) = Decoder.decodeHeader(data);

        // Set up `state` and `notes`. The other values are ancillary and might be used when we need
        // to settle global sell token debt at the end of swapping.
        (
            bytes calldata newData,
            StateLib.State memory state,
            NotesLib.Note[] memory notes,
            ISignatureTransfer.PermitTransferFrom calldata permit,
            bool isForwarded,
            bytes calldata sig
        ) = Decoder.initialize(data, hashMul, hashMod, payer);
        if (payer != address(this)) {
            state.globalSell.amount = _permitToSellAmountCalldata(permit);
        }
        if (feeOnTransfer) {
            state.globalSell.amount =
                _pay(state.globalSell.token, payer, state.globalSell.amount, permit, isForwarded, sig);
        }
        if (state.globalSell.amount == 0) {
            revert ZeroSellAmount(state.globalSell.token);
        }
        state.globalSellAmount = state.globalSell.amount;
        data = newData;

        // Now that we've unpacked and decoded the header, we can begin decoding the array of swaps
        // and executing them.
        IPoolManager.PoolKey memory key;
        IPoolManager.SwapParams memory params;
        while (data.length >= _HOP_DATA_LENGTH) {
            uint16 bps;
            assembly ("memory-safe") {
                bps := shr(0xf0, calldataload(data.offset))

                data.offset := add(0x02, data.offset)
                data.length := sub(data.length, 0x02)
                // we don't check for array out-of-bounds here; we will check it later in `_getHookData`
            }

            data = Decoder.updateState(state, notes, data);
            bool zeroForOne;
            (zeroForOne, data) = _setPoolKey(key, state, data);
            bytes calldata hookData;
            (hookData, data) = Decoder.decodeBytes(data);

            params.zeroForOne = zeroForOne;
            unchecked {
                params.amountSpecified = int256((state.sell.amount * bps).unsafeDiv(BASIS)).unsafeNeg();
            }
            // TODO: price limits
            params.sqrtPriceLimitX96 = zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341;

            BalanceDelta delta = IPoolManager(msg.sender).unsafeSwap(key, params, hookData);
            {
                (int256 settledSellAmount, int256 settledBuyAmount) =
                    zeroForOne ? (delta.amount0(), delta.amount1()) : (delta.amount1(), delta.amount0());
                // Some insane hooks may increase the sell amount; obviously this may result in
                // unavoidable reverts in some cases. But we still need to make sure that we don't
                // underflow to avoid wildly unexpected behavior. The pool manager enforces that the
                // settled sell amount cannot be positive
                state.sell.amount -= uint256(settledSellAmount.unsafeNeg());
                // If `state.buy.amount()` overflows an `int128`, we'll get a revert inside the pool
                // manager later. We cannot overflow a `uint256`.
                unchecked {
                    state.buy.amount += settledBuyAmount.asCredit(state.buy.token);
                }
            }
        }

        // `data` has been consumed. All that remains is to settle out the net result of all the
        // swaps. Any credit in any token other than `state.buy.token` will be swept to
        // Settler. `state.buy.token` will be sent to `recipient`.
        {
            (IERC20 globalSellToken, uint256 globalSellAmount) = (state.globalSell.token, state.globalSell.amount);
            uint256 globalBuyAmount = _take(state, notes, recipient, minBuyAmount);
            if (feeOnTransfer) {
                // We've already transferred the sell token to the pool manager and
                // `settle`'d. `globalSellAmount` is the verbatim credit in that token stored by the
                // pool manager. We only need to handle the case of incomplete filling.
                if (globalSellAmount != 0) {
                    IPoolManager(msg.sender).unsafeTake(
                        globalSellToken, payer == address(this) ? address(this) : _msgSender(), globalSellAmount
                    );
                }
            } else {
                // While `notes` records a credit value, the pool manager actually records a debt
                // for the global sell token. We recover the exact amount of that debt and then pay
                // it.
                // `globalSellAmount` is _usually_ zero, but if it isn't it represents a partial
                // fill. This subtraction recovers the actual debt recorded in the pool manager.
                uint256 debt;
                unchecked {
                    debt = state.globalSellAmount - globalSellAmount;
                }
                if (debt == 0) {
                    revert ZeroSellAmount(globalSellToken);
                }
                if (globalSellToken == ETH_ADDRESS) {
                    IPoolManager(msg.sender).unsafeSettle(debt);
                } else {
                    _pay(globalSellToken, payer, debt, permit, isForwarded, sig);
                }
            }

            bytes memory returndata;
            assembly ("memory-safe") {
                returndata := mload(0x40)
                mstore(returndata, 0x60)
                mstore(add(0x20, returndata), 0x20)
                mstore(add(0x40, returndata), 0x20)
                mstore(add(0x60, returndata), globalBuyAmount)
                mstore(0x40, add(0x80, returndata))
            }
            return returndata;
        }
    }
}
