// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}
