// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

import {BasePairTest} from "./BasePairTest.t.sol";
import {ICurveV2Pool} from "./vendor/ICurveV2Pool.sol";
import {IZeroEx} from "./vendor/IZeroEx.sol";

import {LibBytes} from "../utils/LibBytes.sol";
import {ActionDataBuilder} from "../utils/ActionDataBuilder.sol";

import {SafeTransferLib} from "../../src/utils/SafeTransferLib.sol";

import {Settler} from "../../src/Settler.sol";
import {ISettlerActions} from "../../src/ISettlerActions.sol";
import {OtcOrderSettlement} from "../../src/core/OtcOrderSettlement.sol";

abstract contract SettlerPairTest is BasePairTest {
    using SafeTransferLib for ERC20;
    using LibBytes for bytes;

    uint256 private PERMIT2_FROM_NONCE = 1;
    uint256 private PERMIT2_MAKER_NONCE = 1;

    Settler private settler;
    IZeroEx private ZERO_EX = IZeroEx(0xDef1C0ded9bec7F1a1670819833240f027b25EfF);

    // 0x V4 OTCOrder
    IZeroEx.OtcOrder private otcOrder;
    bytes32 private otcOrderHash;

    function setUp() public virtual override {
        super.setUp();
        settler = getSettler();
        safeApproveIfBelow(fromToken(), FROM, address(PERMIT2), amount());
        // Otc via ZeroEx
        safeApproveIfBelow(toToken(), MAKER, address(ZERO_EX), amount());
        // Otc inside of Settler
        safeApproveIfBelow(toToken(), MAKER, address(PERMIT2), amount());

        // First time inits for Settler
        // We set up allowances to contracts which are inited on the first trade for a fair comparison
        // e.g to a Curve Pool
        ICurveV2Pool.CurveV2PoolData memory poolData = getCurveV2PoolData();
        safeApproveIfBelow(fromToken(), address(settler), address(poolData.pool), amount());
        // ZeroEx for Settler using ZeroEx OTC
        safeApproveIfBelow(fromToken(), address(settler), address(ZERO_EX), amount());

        // Otc 0x v4 order
        otcOrder.makerToken = toToken();
        otcOrder.takerToken = fromToken();
        otcOrder.makerAmount = uint128(amount());
        otcOrder.takerAmount = uint128(amount());
        otcOrder.taker = address(0);
        otcOrder.txOrigin = FROM;
        otcOrder.expiryAndNonce = type(uint256).max;
        otcOrder.maker = MAKER;
        otcOrderHash = ZERO_EX.getOtcOrderHash(otcOrder);

        warmPermit2Nonce(FROM);
        warmPermit2Nonce(MAKER);
    }

    function uniswapV3Path() internal virtual returns (bytes memory);
    function uniswapV2Path() internal virtual returns (bytes memory);
    function getCurveV2PoolData() internal pure virtual returns (ICurveV2Pool.CurveV2PoolData memory);

    function getSettler() private returns (Settler) {
        return new Settler(
            address(PERMIT2),
            0x1F98431c8aD98523631AE4a59f267346ea31F984, // UniV3 Factory
            0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54, // UniV3 pool init code hash
            0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
            0x2222222222222222222222222222222222222222
        );
    }

    function testSettler_zeroExOtcOrder() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MAKER_PRIVATE_KEY, otcOrderHash);

        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    address(ZERO_EX),
                    address(fromToken()),
                    10_000,
                    0x184,
                    abi.encodeCall(
                        ZERO_EX.fillOtcOrder, (otcOrder, IZeroEx.Signature(IZeroEx.SignatureType.EIP712, v, r, s), 0)
                        )
                )
            )
        );

        Settler _settler = settler;
        Settler.AllowedSlippage memory allowedSlippage = Settler.AllowedSlippage({
            buyToken: address(otcOrder.makerToken),
            recipient: FROM,
            minAmountOut: otcOrder.makerAmount
        });
        vm.startPrank(FROM, FROM);
        snapStartName("settler_zeroExOtc");
        _settler.execute(actions, allowedSlippage);
        snapEnd();
    }

    function testSettler_zeroExOtcOrder_partialFill() public {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(MAKER_PRIVATE_KEY, otcOrderHash);

        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    address(ZERO_EX),
                    address(fromToken()),
                    5_000,
                    0x184,
                    abi.encodeCall(
                        ZERO_EX.fillOtcOrder, (otcOrder, IZeroEx.Signature(IZeroEx.SignatureType.EIP712, v, r, s), 0)
                        )
                )
            ),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    address(fromToken()),
                    address(fromToken()),
                    10_000,
                    0x24,
                    abi.encodeCall(fromToken().transfer, (FROM, 0))
                )
            )
        );

        Settler _settler = settler;
        Settler.AllowedSlippage memory allowedSlippage = Settler.AllowedSlippage({
            buyToken: address(otcOrder.makerToken),
            recipient: FROM,
            minAmountOut: otcOrder.makerAmount / 2
        });
        vm.startPrank(FROM, FROM);
        snapStartName("settler_zeroExOtc_partialFill");
        _settler.execute(actions, allowedSlippage);
        snapEnd();
    }

    function testSettler_uniswapV3VIP() public {
        (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory sig) = _getDefaultFromPermit2();
        bytes[] memory actions = ActionDataBuilder.build(
            abi.encodeCall(
                ISettlerActions.UNISWAPV3_PERMIT2_SWAP_EXACT_IN, (FROM, amount(), 0, uniswapV3Path(), permit, sig)
            )
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_uniswapV3VIP");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether})
        );
        snapEnd();
    }

    function testSettler_uniswapV3_multiplex2() public {
        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(ISettlerActions.UNISWAPV3_SWAP_EXACT_IN, (FROM, 5_000, 0, uniswapV3Path())),
            abi.encodeCall(ISettlerActions.UNISWAPV3_SWAP_EXACT_IN, (FROM, 5_000, 0, uniswapV3Path()))
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_uniswapV3_multiplex2");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether})
        );
        snapEnd();
    }

    function testSettler_uniswapV3() public {
        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(ISettlerActions.UNISWAPV3_SWAP_EXACT_IN, (FROM, 10_000, 0, uniswapV3Path()))
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_uniswapV3");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether})
        );
        snapEnd();
    }

    function testSettler_uniswapV3_buyToken_fee_full_custody() public {
        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(ISettlerActions.UNISWAPV3_SWAP_EXACT_IN, (address(settler), 10_000, 0, uniswapV3Path())),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    address(toToken()),
                    address(toToken()),
                    1_000,
                    0x24,
                    abi.encodeCall(toToken().transfer, (BURN_ADDRESS, 0))
                )
            )
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_uniswapV3_buyToken_fee_full_custody");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(toToken()), recipient: FROM, minAmountOut: 0 ether})
        );
        snapEnd();
    }

    function testSettler_uniswapV3_buyToken_fee_single_custody() public {
        (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory sig) = _getDefaultFromPermit2();
        bytes[] memory actions = ActionDataBuilder.build(
            abi.encodeCall(
                ISettlerActions.UNISWAPV3_PERMIT2_SWAP_EXACT_IN,
                (address(settler), amount(), 0, uniswapV3Path(), permit, sig)
            ),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    address(toToken()),
                    address(toToken()),
                    1_000,
                    0x24,
                    abi.encodeCall(toToken().transfer, (BURN_ADDRESS, 0))
                )
            )
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_uniswapV3_buyToken_fee_single_custody");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(toToken()), recipient: FROM, minAmountOut: 0 ether})
        );
        snapEnd();
    }

    function testSettler_uniswapV3_sellToken_fee_full_custody() public {
        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    address(fromToken()),
                    address(fromToken()),
                    1_000,
                    0x24,
                    abi.encodeCall(fromToken().transfer, (BURN_ADDRESS, 0))
                )
            ),
            abi.encodeCall(ISettlerActions.UNISWAPV3_SWAP_EXACT_IN, (FROM, 10_000, 0, uniswapV3Path()))
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_uniswapV3_sellToken_fee_full_custody");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether})
        );
        snapEnd();
    }

    function testSettler_uniswapV2() public {
        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(ISettlerActions.UNISWAPV2_SWAP, (FROM, 10_000, 0, uniswapV2Path()))
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_uniswapV2");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether})
        );
        snapEnd();
    }

    function testSettler_uniswapV2_multihop() public {
        ERC20 wBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(
                ISettlerActions.UNISWAPV2_SWAP,
                (FROM, 10_000, 0, bytes.concat(uniswapV2Path(), bytes1(0x00), bytes20(uint160(address(wBTC)))))
            )
        );

        uint256 balanceBefore = wBTC.balanceOf(FROM);

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_uniswapV2_multihop");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether})
        );
        snapEnd();

        assertGt(wBTC.balanceOf(FROM), balanceBefore);
    }

    function testSettler_curveV2_fee() public skipIf(getCurveV2PoolData().pool == address(0)) {
        ICurveV2Pool.CurveV2PoolData memory poolData = getCurveV2PoolData();

        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    poolData.pool,
                    address(fromToken()),
                    10_000,
                    0x44,
                    abi.encodeCall(ICurveV2Pool.exchange, (poolData.fromTokenIndex, poolData.toTokenIndex, 0, 0))
                )
            ),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    address(toToken()),
                    address(toToken()),
                    1_000,
                    0x24,
                    abi.encodeCall(toToken().transfer, (BURN_ADDRESS, 0))
                )
            ),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (address(toToken()), address(toToken()), 10_000, 0x24, abi.encodeCall(toToken().transfer, (FROM, 0)))
            )
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_curveV2_fee");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether})
        );
        snapEnd();
    }

    function testSettler_basic_curve() public skipIf(getCurveV2PoolData().pool == address(0)) {
        ICurveV2Pool.CurveV2PoolData memory poolData = getCurveV2PoolData();

        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    poolData.pool,
                    address(fromToken()),
                    10_000, // bips
                    0x44, // offset
                    abi.encodeCall(ICurveV2Pool.exchange, (poolData.fromTokenIndex, poolData.toTokenIndex, 0, 0))
                )
            ),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (address(toToken()), address(toToken()), 10_000, 0x24, abi.encodeCall(toToken().transfer, (FROM, 0)))
            )
        );

        uint256 beforeBalance = toToken().balanceOf(FROM);
        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_basic_curve");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether})
        );
        snapEnd();
        assertGt(toToken().balanceOf(FROM), beforeBalance);
    }

    bytes32 private constant CONSIDERATION_TYPEHASH =
        keccak256("Consideration(address token,uint256 amount,address counterparty,bool partialFillAllowed)");
    bytes32 private constant OTC_PERMIT2_WITNESS_TYPEHASH = keccak256(
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,Consideration consideration)Consideration(address token,uint256 amount,address counterparty,bool partialFillAllowed)TokenPermissions(address token,uint256 amount)"
    );
    /*
    bytes32 private constant OTC_PERMIT2_BATCH_WITNESS_TYPEHASH = keccak256(
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,Consideration consideration)Consideration(address token,uint256 amount,address counterparty)TokenPermissions(address token,uint256 amount)"
    );
    */

    struct TakerMetatxnConsideration {
        OtcOrderSettlement.Consideration consideration;
        address recipient;
    }

    bytes32 private constant TAKER_CONSIDERATION_TYPEHASH = keccak256(
        "TakerMetatxnConsideration(Consideration consideration,address recipient)Consideration(address token,uint256 amount,address counterparty,bool partialFillAllowed)"
    );
    bytes32 private constant TAKER_OTC_PERMIT2_WITNESS_TYPEHASH = keccak256(
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,TakerMetatxnConsideration consideration)Consideration(address token,uint256 amount,address counterparty,bool partialFillAllowed)TakerMetatxnConsideration(Consideration consideration,address recipient)TokenPermissions(address token,uint256 amount)"
    );
    /*
    bytes32 private constant TAKER_OTC_PERMIT2_BATCH_WITNESS_TYPEHASH = keccak256(
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,TakerMetatxnConsideration consideration)Consideration(address token,uint256 amount,address counterparty)TakerMetatxnConsideration(Consideration consideration,address recipient)TokenPermissions(address token,uint256 amount)"
    );
    */

    /// @dev Performs an direct OTC trade between MAKER and FROM
    // Funds are transferred MAKER->FROM and FROM->MAKER
    function testSettler_otc() public {
        ISignatureTransfer.PermitTransferFrom memory makerPermit =
            defaultERC20PermitTransfer(address(toToken()), amount(), PERMIT2_MAKER_NONCE);
        ISignatureTransfer.PermitTransferFrom memory takerPermit =
            defaultERC20PermitTransfer(address(fromToken()), amount(), PERMIT2_FROM_NONCE);

        OtcOrderSettlement.Consideration memory makerConsideration = OtcOrderSettlement.Consideration({
            token: address(fromToken()),
            amount: amount(),
            counterparty: FROM,
            partialFillAllowed: false
        });

        bytes32 makerWitness = keccak256(bytes.concat(CONSIDERATION_TYPEHASH, abi.encode(makerConsideration)));
        bytes memory makerSig = getPermitWitnessTransferSignature(
            makerPermit,
            address(settler),
            MAKER_PRIVATE_KEY,
            OTC_PERMIT2_WITNESS_TYPEHASH,
            makerWitness,
            PERMIT2.DOMAIN_SEPARATOR()
        );

        bytes memory takerSig =
            getPermitTransferSignature(takerPermit, address(settler), FROM_PRIVATE_KEY, PERMIT2.DOMAIN_SEPARATOR());

        bytes[] memory actions = ActionDataBuilder.build(
            abi.encodeCall(ISettlerActions.SETTLER_OTC_PERMIT2, (makerPermit, MAKER, makerSig, takerPermit, takerSig))
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_otc");
        _settler.execute(
            actions, Settler.AllowedSlippage({buyToken: address(0), recipient: FROM, minAmountOut: 0 ether})
        );
        snapEnd();
    }

    bytes32 private constant FULL_PERMIT2_WITNESS_TYPEHASH = keccak256(
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,ActionsAndSlippage actionsAndSlippage)ActionsAndSlippage(bytes[] actions,address buyToken,address recipient,uint256 minAmountOut)TokenPermissions(address token,uint256 amount)"
    );
    bytes32 private constant ACTIONS_AND_SLIPPAGE_TYPEHASH =
        keccak256("ActionsAndSlippage(bytes[] actions,address buyToken,address recipient,uint256 minAmountOut)");

    function testSettler_metaTxn_uniswapV3() public {
        ISignatureTransfer.PermitTransferFrom memory permit =
            defaultERC20PermitTransfer(address(fromToken()), amount(), PERMIT2_FROM_NONCE);

        bytes[] memory actions = ActionDataBuilder.build(
            abi.encodeCall(ISettlerActions.METATXN_PERMIT2_TRANSFER_FROM, (address(settler), permit)),
            abi.encodeCall(ISettlerActions.UNISWAPV3_SWAP_EXACT_IN, (FROM, 10_000, 0, uniswapV3Path()))
        );

        bytes32[] memory actionHashes = new bytes32[](actions.length);
        for (uint256 i; i < actionHashes.length; i++) {
            actionHashes[i] = keccak256(actions[i]);
        }
        bytes32 actionsHash = keccak256(abi.encodePacked(actionHashes));
        bytes32 witness =
            keccak256(abi.encode(ACTIONS_AND_SLIPPAGE_TYPEHASH, actionsHash, address(0), address(0), 0 ether));
        bytes memory sig = getPermitWitnessTransferSignature(
            permit,
            address(settler),
            FROM_PRIVATE_KEY,
            FULL_PERMIT2_WITNESS_TYPEHASH,
            witness,
            PERMIT2.DOMAIN_SEPARATOR()
        );

        Settler _settler = settler;
        // Submitted by third party
        vm.startPrank(address(this), address(this)); // does a `call` to keep the optimizer from reordering opcodes
        snapStartName("settler_metaTxn_uniswapV3");
        _settler.executeMetaTxn(
            actions,
            Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether}),
            FROM,
            sig
        );
        snapEnd();
    }

    function testSettler_metaTxn_uniswapV3VIP() public {
        ISignatureTransfer.PermitTransferFrom memory permit =
            defaultERC20PermitTransfer(address(fromToken()), amount(), PERMIT2_FROM_NONCE);

        bytes[] memory actions = ActionDataBuilder.build(
            abi.encodeCall(
                ISettlerActions.METATXN_UNISWAPV3_PERMIT2_SWAP_EXACT_IN, (FROM, amount(), 0, uniswapV3Path(), permit)
            )
        );

        bytes32[] memory actionHashes = new bytes32[](actions.length);
        for (uint256 i; i < actionHashes.length; i++) {
            actionHashes[i] = keccak256(actions[i]);
        }
        bytes32 actionsHash = keccak256(abi.encodePacked(actionHashes));
        bytes32 witness =
            keccak256(abi.encode(ACTIONS_AND_SLIPPAGE_TYPEHASH, actionsHash, address(0), address(0), 0 ether));
        bytes memory sig = getPermitWitnessTransferSignature(
            permit,
            address(settler),
            FROM_PRIVATE_KEY,
            FULL_PERMIT2_WITNESS_TYPEHASH,
            witness,
            PERMIT2.DOMAIN_SEPARATOR()
        );

        Settler _settler = settler;
        // Submitted by third party
        vm.startPrank(address(this), address(this)); // does a `call` to keep the optimizer from reordering opcodes
        snapStartName("settler_metaTxn_uniswapV3VIP");
        _settler.executeMetaTxn(
            actions,
            Settler.AllowedSlippage({buyToken: address(0), recipient: address(0), minAmountOut: 0 ether}),
            FROM,
            sig
        );
        snapEnd();
    }

    function testSettler_metaTxn_otc() public {
        ISignatureTransfer.PermitTransferFrom memory makerPermit =
            defaultERC20PermitTransfer(address(toToken()), amount(), PERMIT2_MAKER_NONCE);
        ISignatureTransfer.PermitTransferFrom memory takerPermit =
            defaultERC20PermitTransfer(address(fromToken()), amount(), PERMIT2_FROM_NONCE);

        OtcOrderSettlement.Consideration memory makerConsideration = OtcOrderSettlement.Consideration({
            token: address(fromToken()),
            amount: amount(),
            counterparty: FROM,
            partialFillAllowed: false
        });
        bytes32 makerWitness = keccak256(bytes.concat(CONSIDERATION_TYPEHASH, abi.encode(makerConsideration)));
        bytes memory makerSig = getPermitWitnessTransferSignature(
            makerPermit,
            address(settler),
            MAKER_PRIVATE_KEY,
            OTC_PERMIT2_WITNESS_TYPEHASH,
            makerWitness,
            PERMIT2.DOMAIN_SEPARATOR()
        );

        TakerMetatxnConsideration memory takerConsideration = TakerMetatxnConsideration({
            consideration: OtcOrderSettlement.Consideration({
                token: address(toToken()),
                amount: amount(),
                counterparty: MAKER,
                partialFillAllowed: false
            }),
            recipient: FROM
        });
        bytes32 takerWitness = keccak256(
            bytes.concat(
                TAKER_CONSIDERATION_TYPEHASH,
                abi.encode(
                    keccak256(bytes.concat(CONSIDERATION_TYPEHASH, abi.encode(takerConsideration.consideration))), FROM
                )
            )
        );
        bytes memory takerSig = getPermitWitnessTransferSignature(
            takerPermit,
            address(settler),
            FROM_PRIVATE_KEY,
            TAKER_OTC_PERMIT2_WITNESS_TYPEHASH,
            takerWitness,
            PERMIT2.DOMAIN_SEPARATOR()
        );

        bytes[] memory actions = ActionDataBuilder.build(
            abi.encodeCall(ISettlerActions.METATXN_SETTLER_OTC_PERMIT2, (makerPermit, MAKER, makerSig, takerPermit))
        );

        Settler _settler = settler;
        // Submitted by third party
        vm.startPrank(address(this), address(this)); // does a `call` to keep the optimizer from reordering opcodes
        snapStartName("settler_metaTxn_otc");
        _settler.executeMetaTxn(
            actions,
            Settler.AllowedSlippage({buyToken: address(0), recipient: FROM, minAmountOut: 0 ether}),
            FROM,
            takerSig
        );
        snapEnd();
    }

    /// @dev Performs a direct OTC trade between MAKER and FROM but with Settler receiving the sell and buy token funds.
    /// Funds transfer
    ///   OTC
    ///     TAKER->Settler
    ///     MAKER->Settler
    ///     Settler->MAKER
    ///   TRANSFER_OUT_PROPORTIONAL
    ///     Settler->FEE_RECIPIENT
    ///   SLIPPAGE
    ///     Settler->FROM
    function testSettler_otc_fee_full_custody() public {
        ISignatureTransfer.PermitTransferFrom memory makerPermit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(toToken()), amount: amount()}),
            nonce: PERMIT2_MAKER_NONCE,
            deadline: block.timestamp + 100
        });
        OtcOrderSettlement.Consideration memory makerConsideration = OtcOrderSettlement.Consideration({
            token: address(fromToken()),
            amount: amount(),
            counterparty: FROM,
            partialFillAllowed: true
        });
        bytes32 makerWitness = keccak256(bytes.concat(CONSIDERATION_TYPEHASH, abi.encode(makerConsideration)));
        bytes memory makerSig = getPermitWitnessTransferSignature(
            makerPermit,
            address(settler),
            MAKER_PRIVATE_KEY,
            OTC_PERMIT2_WITNESS_TYPEHASH,
            makerWitness,
            PERMIT2.DOMAIN_SEPARATOR()
        );

        bytes[] memory actions = ActionDataBuilder.build(
            _getDefaultFromPermit2Action(),
            abi.encodeCall(
                ISettlerActions.SETTLER_OTC_SELF_FUNDED,
                (address(settler), makerPermit, MAKER, makerSig, address(fromToken()), amount())
            ),
            abi.encodeCall(
                ISettlerActions.BASIC_SELL,
                (
                    address(toToken()),
                    address(toToken()),
                    1_000,
                    0x24,
                    abi.encodeCall(toToken().transfer, (BURN_ADDRESS, 0))
                )
            )
        );

        Settler _settler = settler;
        vm.startPrank(FROM);
        snapStartName("settler_otc_fee_full_custody");
        _settler.execute(
            actions,
            Settler.AllowedSlippage({
                buyToken: address(toToken()),
                recipient: FROM,
                minAmountOut: amount() * 9_000 / 10_000
            })
        );
        snapEnd();
    }

    function _getDefaultFromPermit2Action() private returns (bytes memory) {
        (ISignatureTransfer.PermitTransferFrom memory permit, bytes memory sig) = _getDefaultFromPermit2();
        return abi.encodeCall(ISettlerActions.PERMIT2_TRANSFER_FROM, (address(settler), permit, sig));
    }

    function _getDefaultFromPermit2() private returns (ISignatureTransfer.PermitTransferFrom memory, bytes memory) {
        ISignatureTransfer.PermitTransferFrom memory permit =
            defaultERC20PermitTransfer(address(fromToken()), amount(), PERMIT2_FROM_NONCE);
        bytes memory sig =
            getPermitTransferSignature(permit, address(settler), FROM_PRIVATE_KEY, PERMIT2.DOMAIN_SEPARATOR());
        return (permit, sig);
    }
}
