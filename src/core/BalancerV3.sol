// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@forge-std/interfaces/IERC20.sol";
import {IERC4626} from "@forge-std/interfaces/IERC4626.sol";
import {ISignatureTransfer} from "@permit2/interfaces/ISignatureTransfer.sol";
import {SafeTransferLib} from "../vendor/SafeTransferLib.sol";
import {SettlerAbstract} from "../SettlerAbstract.sol";

import {Panic} from "../utils/Panic.sol";
import {UnsafeMath} from "../utils/UnsafeMath.sol";

import {
    TooMuchSlippage,
    ZeroSellAmount
} from "./SettlerErrors.sol";

import {Encoder, NotesLib, StateLib, Decoder, Take} from "./FlashAccountingCommon.sol";

import {FreeMemory} from "../utils/FreeMemory.sol";

interface IBalancerV3Vault {
    /**
     * @notice Creates a context for a sequence of operations (i.e., "unlocks" the Vault).
     * @dev Performs a callback on msg.sender with arguments provided in `data`. The Callback is `transient`,
     * meaning all balances for the caller have to be settled at the end.
     *
     * @param data Contains function signature and args to be passed to the msg.sender
     * @return result Resulting data from the call
     */
    function unlock(bytes calldata data) external returns (bytes memory);

    /**
     * @notice Settles deltas for a token; must be successful for the current lock to be released.
     * @dev Protects the caller against leftover dust in the Vault for the token being settled. The caller
     * should know in advance how many tokens were paid to the Vault, so it can provide it as a hint to discard any
     * excess in the Vault balance.
     *
     * If the given hint is equal to or higher than the difference in reserves, the difference in reserves is given as
     * credit to the caller. If it's higher, the caller sent fewer tokens than expected, so settlement would fail.
     *
     * If the given hint is lower than the difference in reserves, the hint is given as credit to the caller.
     * In this case, the excess would be absorbed by the Vault (and reflected correctly in the reserves), but would
     * not affect settlement.
     *
     * The credit supplied by the Vault can be calculated as `min(reserveDifference, amountHint)`, where the reserve
     * difference equals current balance of the token minus existing reserves of the token when the function is called.
     *
     * @param token Address of the token
     * @param amountHint Amount paid as reported by the caller
     * @return credit Credit received in return of the payment
     */
    function settle(IERC20 token, uint256 amountHint) external returns (uint256 credit);

    /**
     * @notice Sends tokens to a recipient.
     * @dev There is no inverse operation for this function. Transfer funds to the Vault and call `settle` to cancel
     * debts.
     *
     * @param token Address of the token
     * @param to Recipient address
     * @param amount Amount of tokens to send
     */
    function sendTo(IERC20 token, address to, uint256 amount) external;

    enum SwapKind {
        EXACT_IN,
        EXACT_OUT
    }

    /**
     * @notice Data passed into primary Vault `swap` operations.
     * @param kind Type of swap (Exact In or Exact Out)
     * @param pool The pool with the tokens being swapped
     * @param tokenIn The token entering the Vault (balance increases)
     * @param tokenOut The token leaving the Vault (balance decreases)
     * @param amountGiven Amount specified for tokenIn or tokenOut (depending on the type of swap)
     * @param limit Minimum or maximum value of the calculated amount (depending on the type of swap)
     * @param userData Additional (optional) user data
     */
    struct VaultSwapParams {
        SwapKind kind;
        address pool;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGiven;
        uint256 limit;
        bytes userData;
    }

    /**
     * @notice Swaps tokens based on provided parameters.
     * @dev All parameters are given in raw token decimal encoding.
     * @param vaultSwapParams Parameters for the swap (see above for struct definition)
     * @return amountCalculated Calculated swap amount
     * @return amountIn Amount of input tokens for the swap
     * @return amountOut Amount of output tokens from the swap
     */
    function swap(VaultSwapParams memory vaultSwapParams)
        external
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);

    enum WrappingDirection {
        WRAP,
        UNWRAP
    }

    /**
     * @notice Data for a wrap/unwrap operation.
     * @param kind Type of swap (Exact In or Exact Out)
     * @param direction Direction of the wrapping operation (Wrap or Unwrap)
     * @param wrappedToken Wrapped token, compatible with interface ERC4626
     * @param amountGiven Amount specified for tokenIn or tokenOut (depends on the type of swap and wrapping direction)
     * @param limit Minimum or maximum amount specified for the other token (depends on the type of swap and wrapping
     * direction)
     */
    struct BufferWrapOrUnwrapParams {
        SwapKind kind;
        WrappingDirection direction;
        IERC4626 wrappedToken;
        uint256 amountGiven;
        uint256 limit;
    }

    /**
     * @notice Wraps/unwraps tokens based on the parameters provided.
     * @dev All parameters are given in raw token decimal encoding. It requires the buffer to be initialized,
     * and uses the internal wrapped token buffer when it has enough liquidity to avoid external calls.
     *
     * @param params Parameters for the wrap/unwrap operation (see struct definition)
     * @return amountCalculated Calculated swap amount
     * @return amountIn Amount of input tokens for the swap
     * @return amountOut Amount of output tokens from the swap
     */
    function erc4626BufferWrapOrUnwrap(BufferWrapOrUnwrapParams memory params)
        external
        returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut);
}

IBalancerV3Vault constant VAULT = IBalancerV3Vault(0xbA1333333333a1BA1108E8412f11850A5C319bA9);

interface IBalancerV3Callback {
    function balancerUnlockCallback(bytes calldata data) external returns (bytes memory);
}

abstract contract BalancerV3 is SettlerAbstract, FreeMemory {
    using SafeTransferLib for IERC20;
    using UnsafeMath for uint256;
    using NotesLib for NotesLib.Note;
    using NotesLib for NotesLib.Note[];
    using StateLib for StateLib.State;

    constructor() {
        assert(BASIS == Encoder.BASIS);
        assert(BASIS == Decoder.BASIS);
        assert(ETH_ADDRESS == Decoder.ETH_ADDRESS);
    }

    function sellToBalancerV3(
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
        bytes memory data = Encoder.encode(
            uint32(IBalancerV3Vault.unlock.selector),
            recipient,
            sellToken,
            bps,
            feeOnTransfer,
            hashMul,
            hashMod,
            fills,
            amountOutMin
        );
        bytes memory encodedBuyAmount = _setOperatorAndCall(
            address(VAULT), data, uint32(IBalancerV3Callback.balancerUnlockCallback.selector), _balV3Callback
        );
        // buyAmount = abi.decode(abi.decode(encodedBuyAmount, (bytes)), (uint256));
        assembly ("memory-safe") {
            // We can skip all the checks performed by `abi.decode` because we know that this is the
            // verbatim result from `balancerUnlockCallback` and that `balancerUnlockCallback`
            // encoded the buy amount correctly.
            buyAmount := mload(add(0x60, encodedBuyAmount))
        }
    }

    function sellToBalancerV3VIP(
        address recipient,
        bool feeOnTransfer,
        uint256 hashMul,
        uint256 hashMod,
        bytes memory fills,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes memory sig,
        uint256 amountOutMin
    ) internal returns (uint256 buyAmount) {
        bytes memory data = Encoder.encodeVIP(
            uint32(IBalancerV3Vault.unlock.selector),
            recipient,
            feeOnTransfer,
            hashMul,
            hashMod,
            fills,
            permit,
            sig,
            _isForwarded(),
            amountOutMin
        );
        bytes memory encodedBuyAmount = _setOperatorAndCall(
            address(VAULT), data, uint32(IBalancerV3Callback.balancerUnlockCallback.selector), _balV3Callback
        );
        // buyAmount = abi.decode(abi.decode(encodedBuyAmount, (bytes)), (uint256));
        assembly ("memory-safe") {
            // We can skip all the checks performed by `abi.decode` because we know that this is the
            // verbatim result from `balancerUnlockCallback` and that `balancerUnlockCallback`
            // encoded the buy amount correctly.
            buyAmount := mload(add(0x60, encodedBuyAmount))
        }
    }

    function _balV3Callback(bytes calldata data) private returns (bytes memory) {
        // We know that our calldata is well-formed. Therefore, the first slot is 0x20 and the
        // second slot is the length of the strict ABIEncoded payload
        assembly ("memory-safe") {
            data.length := calldataload(add(0x20, data.offset))
            data.offset := add(0x40, data.offset)
        }
        return balancerUnlockCallback(data);
    }

    function _setSwapParams(
        IBalancerV3Vault.VaultSwapParams memory swapParams,
        StateLib.State memory state,
        bytes calldata data
    ) internal view returns (bytes calldata) {
        assembly ("memory-safe") {
            mstore(add(0x20, swapParams), shr(0x60, calldataload(data.offset)))
            data.offset := add(0x14, data.offset)
            data.length := sub(data.length, 0x14)
            // we don't check for array out-of-bounds here; we will check it later in `Decoder.decodeBytes`
        }
        swapParams.tokenIn = state.sell.token;
        swapParams.tokenOut = state.buy.token;
        return data;
    }

    function _decodeUserdataAndSwap(
        IBalancerV3Vault.VaultSwapParams memory swapParams,
        StateLib.State memory state,
        bytes calldata data
    ) internal DANGEROUS_freeMemory returns (bytes calldata) {
        (data, swapParams.userData) = Decoder.decodeBytes(data);

        (, uint256 amountIn, uint256 amountOut) = IBalancerV3Vault(msg.sender).swap(swapParams);
        state.sell.amount -= amountIn;
        state.buy.amount += amountOut;

        swapParams.userData = new bytes(0);

        return data;
    }

    function _pay(
        IERC20 sellToken,
        address payer,
        uint256 sellAmount,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bool isForwarded,
        bytes calldata sig
    ) private returns (uint256) {
        if (payer == address(this)) {
            sellToken.safeTransfer(msg.sender, sellAmount);
        } else {
            // assert(payer == address(0));
            ISignatureTransfer.SignatureTransferDetails memory transferDetails =
                ISignatureTransfer.SignatureTransferDetails({to: msg.sender, requestedAmount: sellAmount});
            _transferFrom(permit, transferDetails, sig, isForwarded);
        }
        return IBalancerV3Vault(msg.sender).settle(sellToken, sellAmount);
    }

    // the mandatory fields are
    // 2 - sell bps
    // 1 - pool key tokens case
    // 20 - pool
    // 3 - user data length
    uint256 private constant _HOP_DATA_LENGTH = 26;

    function balancerUnlockCallback(bytes calldata data) private returns (bytes memory) {
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

        IBalancerV3Vault.VaultSwapParams memory swapParams;
        swapParams.kind = IBalancerV3Vault.SwapKind.EXACT_IN;
        swapParams.limit = 0; // TODO: price limits for partial filling
        while (data.length >= _HOP_DATA_LENGTH) {
            uint16 bps;
            assembly ("memory-safe") {
                bps := shr(0xf0, calldataload(data.offset))

                data.offset := add(0x02, data.offset)
                data.length := sub(data.length, 0x02)
                // we don't check for array out-of-bounds here; we will check it later in `Decoder.decodeBytes`
            }

            // TODO: ERC4623 wrap/unwrap

            data = Decoder.updateState(state, notes, data);
            data = _setSwapParams(swapParams, state, data);
            swapParams.amountGiven = (state.sell.amount * bps).unsafeDiv(BASIS);
            data = _decodeUserdataAndSwap(swapParams, state, data);
        }


        // `data` has been consumed. All that remains is to settle out the net result of all the
        // swaps. Any credit in any token other than `state.buy.token` will be swept to
        // Settler. `state.buy.token` will be sent to `recipient`.
        {
            (IERC20 globalSellToken, uint256 globalSellAmount) = (state.globalSell.token, state.globalSell.amount);
            uint256 globalBuyAmount = Take.take(state, notes, uint32(IBalancerV3Vault.sendTo.selector), recipient, minBuyAmount);
            if (feeOnTransfer) {
                // We've already transferred the sell token to the pool manager and
                // `settle`'d. `globalSellAmount` is the verbatim credit in that token stored by the
                // pool manager. We only need to handle the case of incomplete filling.
                if (globalSellAmount != 0) {
                    Take._callSelector(uint32(IBalancerV3Vault.sendTo.selector), globalSellToken, payer == address(this) ? address(this) : _msgSender(), globalSellAmount);
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
                _pay(globalSellToken, payer, debt, permit, isForwarded, sig);
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
