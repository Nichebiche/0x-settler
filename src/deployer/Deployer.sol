// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165, AbstractOwnable} from "./TwoStepOwnable.sol";
import {ERC1967UUPSUpgradeable, ERC1967TwoStepOwnable} from "../proxy/ERC1967UUPSUpgradeable.sol";
import {Context} from "../Context.sol";
import {Panic} from "../utils/Panic.sol";
import {Create3} from "../utils/Create3.sol";
import {IPFS} from "../utils/IPFS.sol";
import {ItoA} from "../utils/ItoA.sol";
import {MultiCall} from "../utils/MultiCall.sol";

interface IERC721View is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function balanceOf(address) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC721ViewMetadata is IERC721View {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256) external view returns (string memory);
}

type Nonce is uint32;

function incr(Nonce a) pure returns (Nonce) {
    return Nonce.wrap(Nonce.unwrap(a) + 1);
}

function gt(Nonce a, Nonce b) pure returns (bool) {
    return Nonce.unwrap(a) > Nonce.unwrap(b);
}

function isNull(Nonce a) pure returns (bool) {
    return Nonce.unwrap(a) == 0;
}

using {gt as >, incr, isNull} for Nonce global;

Nonce constant zero = Nonce.wrap(0);

library NonceList {
    struct ListElem {
        Nonce prev;
        Nonce next;
    }

    struct List {
        ListElem[4294967296] links;
        Nonce head;
        Nonce highWater;
        Nonce lastNonce;
    }

    function get(ListElem[4294967296] storage links, Nonce i) internal pure returns (ListElem storage r) {
        assembly ("memory-safe") {
            r.slot := add(links.slot, and(0xffffffff, i))
        }
    }
}

contract Deployer is ERC1967UUPSUpgradeable, Context, ERC1967TwoStepOwnable, IERC721ViewMetadata, MultiCall {
    using NonceList for NonceList.ListElem[4294967296];

    struct FeatureInfo {
        NonceList.List list;
        address auth;
        uint40 deadline;
        bytes32 descriptionHash;
    }

    struct DeployInfo {
        uint128 feature;
        Nonce nonce;
    }

    /// @custom:storage-location erc7201:0xV5Deployer.1
    struct ZeroExV5DeployerStorage1 {
        mapping(uint128 => FeatureInfo) featureInfo;
        mapping(address => DeployInfo) deployInfo;
    }

    uint256 private constant _BASE_SLOT = 0x6fc90c2fe4d07a554a5baba07c2807f581f77bd906c5068b416617fdd1427800;

    function _stor1() private pure returns (ZeroExV5DeployerStorage1 storage r) {
        assembly ("memory-safe") {
            r.slot := _BASE_SLOT
        }
    }

    function authorized(uint128 feature) external view returns (address auth, uint40 deadline) {
        FeatureInfo storage result = _stor1().featureInfo[feature];
        (auth, deadline) = (result.auth, result.deadline);
    }

    function descriptionHash(uint128 feature) external view returns (bytes32) {
        return _stor1().featureInfo[feature].descriptionHash;
    }

    constructor() ERC1967UUPSUpgradeable(1) {
        ZeroExV5DeployerStorage1 storage stor1 = _stor1();
        // storage starts at the slot defined by ERC7201
        {
            bytes32 slot;
            assembly ("memory-safe") {
                slot := stor1.slot
            }
            assert(
                slot == keccak256(abi.encodePacked(uint256(keccak256("0xV5Deployer.1")) - 1)) & ~bytes32(uint256(0xff))
            );
        }

        // `ListElem` does not pack because it is a struct
        {
            NonceList.ListElem storage linkZero = stor1.featureInfo[0].list.links[0];
            NonceList.ListElem storage linkOne = stor1.featureInfo[0].list.links[1];
            uint256 slotZero;
            uint256 slotOne;
            assembly ("memory-safe") {
                slotZero := linkZero.slot
                slotOne := linkOne.slot
            }
            assert(slotZero + 1 == slotOne);
        }
    }

    function initialize(address initialOwner) external {
        _setPendingOwner(initialOwner);
        super._initialize();
    }

    function _salt(uint128 feature, Nonce nonce) internal pure returns (bytes32) {
        return bytes32(uint256(feature) << 128 | uint256(Nonce.unwrap(nonce)));
    }

    function next(uint128 feature) external view returns (address) {
        return Create3.predict(_salt(feature, _stor1().featureInfo[feature].list.lastNonce.incr()));
    }

    error FeatureNotInitialized(uint128);

    event Authorized(uint128 indexed, address indexed, uint40);

    function authorize(uint128 feature, address auth, uint40 deadline) public onlyOwner returns (bool) {
        require((auth == address(0)) == (block.timestamp > deadline));
        if (feature == 0) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        FeatureInfo storage featureInfo = _stor1().featureInfo[feature];
        if (featureInfo.descriptionHash == 0) {
            revert FeatureNotInitialized(feature);
        }
        emit Authorized(feature, auth, deadline);
        (featureInfo.auth, featureInfo.deadline) = (auth, deadline);
        return true;
    }

    function _requireAuthorized(uint128 feature) internal view returns (FeatureInfo storage featureInfo) {
        featureInfo = _stor1().featureInfo[feature];
        (address auth, uint40 deadline) = (featureInfo.auth, featureInfo.deadline);
        if (_msgSender() != auth || (deadline != type(uint40).max && block.timestamp > deadline)) {
            revert PermissionDenied();
        }
    }

    event PermanentURI(string, uint256 indexed);

    error FeatureInitialized(uint128);

    function setDescription(uint128 feature, string calldata description)
        public
        onlyOwner
        returns (string memory content)
    {
        FeatureInfo storage featureInfo = _stor1().featureInfo[feature];
        if (featureInfo.descriptionHash != 0) {
            revert FeatureInitialized(feature);
        }
        content = string.concat(
            "{\"description\": \"", description, "\", \"name\": \"0xV5 feature ", ItoA.itoa(feature), "\"}\n"
        );
        bytes32 contentHash = IPFS.dagPbUnixFsHash(content);
        featureInfo.descriptionHash = contentHash;
        emit PermanentURI(IPFS.CIDv0(contentHash), feature);
    }

    event Deployed(uint128 indexed, Nonce indexed, address indexed);

    error DeployFailed(Nonce);

    function deploy(uint128 feature, bytes calldata initCode)
        public
        payable
        returns (address predicted, Nonce thisNonce)
    {
        FeatureInfo storage featureInfo = _requireAuthorized(feature);
        NonceList.List storage featureList = featureInfo.list;
        Nonce prevNonce;
        (prevNonce, thisNonce) = (featureList.head, featureList.lastNonce.incr());
        (featureList.head, featureList.lastNonce) = (thisNonce, thisNonce);

        bytes32 salt = _salt(feature, thisNonce);
        predicted = Create3.predict(salt);
        _stor1().deployInfo[predicted] = DeployInfo({feature: feature, nonce: thisNonce});
        emit Deployed(feature, thisNonce, predicted);

        {
            NonceList.ListElem storage dst = featureList.links.get(thisNonce);
            (dst.prev, dst.next) = (prevNonce, zero);
        }
        if (prevNonce.isNull()) {
            emit Transfer(address(0), predicted, feature);
        } else {
            emit Transfer(Create3.predict(_salt(feature, prevNonce)), predicted, feature);
            featureList.links.get(prevNonce).next = thisNonce;
        }

        if (Create3.createFromCalldata(salt, initCode, msg.value) != predicted || predicted.code.length == 0) {
            revert DeployFailed(thisNonce);
        }
    }

    error FutureDeployment(Nonce);

    event Removed(uint128 indexed, Nonce indexed, address indexed);

    function remove(uint128 feature, Nonce nonce) public returns (bool) {
        FeatureInfo storage featureInfo = _requireAuthorized(feature);
        NonceList.List storage featureList = featureInfo.list;
        if (nonce > featureList.lastNonce) {
            revert FutureDeployment(nonce);
        }
        NonceList.ListElem storage entry = featureList.links.get(nonce);

        (Nonce prevNonce, Nonce nextNonce) = (entry.prev, entry.next);
        address deployment = Create3.predict(_salt(feature, nonce));
        if (nextNonce.isNull()) {
            if (nonce > featureList.highWater) {
                // assert(head.head == nonce);
                featureList.head = prevNonce;
                emit Transfer(
                    deployment, prevNonce.isNull() ? address(0) : Create3.predict(_salt(feature, prevNonce)), feature
                );
            }
        } else {
            featureList.links.get(nextNonce).prev = prevNonce;
        }
        if (!prevNonce.isNull()) {
            featureList.links.get(prevNonce).next = nextNonce;
        }
        (entry.prev, entry.next) = (zero, zero);

        emit Removed(feature, nonce, deployment);
        return true;
    }

    event RemovedAll(uint128 indexed);

    function removeAll(uint128 feature) public returns (bool) {
        NonceList.List storage featureList = _requireAuthorized(feature).list;
        Nonce nonce;
        (nonce, featureList.head, featureList.highWater) = (featureList.head, zero, featureList.lastNonce);
        if (!nonce.isNull()) {
            emit Transfer(Create3.predict(_salt(feature, nonce)), address(0), feature);
        }
        emit RemovedAll(feature);
        return true;
    }

    string public constant override name = "0xV5";
    string public constant override symbol = "0xV5";

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, AbstractOwnable, ERC1967UUPSUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId) || interfaceId == 0x80ac58cd // regular IERC721
            || interfaceId == type(IERC721ViewMetadata).interfaceId;
    }

    function balanceOf(address instance) external view override returns (uint256) {
        if (instance == address(0)) {
            revert ZeroAddress();
        }
        ZeroExV5DeployerStorage1 storage stor1 = _stor1();
        DeployInfo storage info = stor1.deployInfo[instance];
        (uint128 feature, Nonce nonce) = (info.feature, info.nonce);
        if (feature == 0) {
            return 0;
        }
        NonceList.List storage featureList = stor1.featureInfo[feature].list;
        if (nonce > featureList.highWater && featureList.links.get(nonce).next.isNull()) {
            return 1;
        }
        return 0;
    }

    error NoToken(uint256);

    function _requireTokenExists(uint256 tokenId) private view returns (Nonce nonce) {
        if (tokenId > type(uint128).max) {
            Panic.panic(Panic.ARITHMETIC_OVERFLOW);
        }
        if ((nonce = _stor1().featureInfo[uint128(tokenId)].list.head).isNull()) {
            revert NoToken(tokenId);
        }
    }

    function ownerOf(uint256 tokenId) external view override returns (address) {
        return Create3.predict(_salt(uint128(tokenId), _requireTokenExists(tokenId)));
    }

    modifier tokenExists(uint256 tokenId) {
        _requireTokenExists(tokenId);
        _;
    }

    function getApproved(uint256 tokenId) external view override tokenExists(tokenId) returns (address) {
        return address(0);
    }

    function isApprovedForAll(address, address) external pure override returns (bool) {
        return false;
    }

    function tokenURI(uint256 tokenId) external view override tokenExists(tokenId) returns (string memory) {
        return IPFS.CIDv0(_stor1().featureInfo[uint128(tokenId)].descriptionHash);
    }

    // solc is dumb

    function owner() public view override(ERC1967UUPSUpgradeable, AbstractOwnable) returns (address) {
        return super.owner();
    }
}
