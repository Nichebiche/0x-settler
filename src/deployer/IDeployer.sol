// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165, IOwnable} from "./TwoStepOwnable.sol";
import {IERC1967Proxy} from "../proxy/ERC1967UUPSUpgradeable.sol";
import {IMultiCall} from "../utils/MultiCall.sol";
import {Feature} from "./Feature.sol";
import {Nonce} from "./Nonce.sol";

interface IERC721View is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event PermanentURI(string, uint256 indexed);

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

interface IDeployer is IOwnable, IERC721ViewMetadata, IMultiCall {
    function authorized(Feature) external view returns (address, uint40);
    function descriptionHash(Feature) external view returns (bytes32);
    function next(Feature) external view returns (address);
    function deployInfo(address) external view returns (Feature, Nonce);
    function authorize(Feature, address, uint40) external returns (bool);
    function setDescription(Feature, string calldata) external returns (string memory);
    function deploy(Feature, bytes calldata) external payable returns (address, Nonce);
    function remove(Feature, Nonce) external returns (bool);
    function remove(address) external returns (bool);
    function removeAll(Feature) external returns (bool);

    error NotDeployed(address);
    error FeatureNotInitialized(Feature);
    error FeatureInitialized(Feature);
    error DeployFailed(Feature, Nonce, address);
    error NoToken(uint256);
    error FutureNonce(Nonce);

    event Authorized(Feature indexed, address indexed, uint40);
    event Deployed(Feature indexed, Nonce indexed, address indexed);
    event Removed(Feature indexed, Nonce indexed, address indexed);
    event RemovedAll(Feature indexed);
}
