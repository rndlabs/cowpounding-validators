// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IERC677 {
    function transferAndCall(address recipient, uint256 amount, bytes calldata data) external returns (bool);
}
