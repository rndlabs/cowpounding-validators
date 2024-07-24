// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface Settlement {
    function domainSeparator() external view returns (bytes32);
}
