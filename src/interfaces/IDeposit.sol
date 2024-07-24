// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IDeposit {
    function claimWithdrawal(address who) external;
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root,
        uint256 stake_amount
    ) external payable;
    function withdrawableAmount(address who) external view returns (uint256);
}
