// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {GPv2Order} from "src/libraries/GPv2Order.sol";

/**
 * @title Conditional Order Interface
 * @author CoW Protocol Developers
 */
interface IConditionalOrder {
    /// @dev This error is returned by the `getTradeableOrder` function if the order condition is not met.
    ///      A parameter of `string` type is included to allow the caller to specify the reason for the failure.
    error OrderNotValid(string);

    // --- errors specific for polling
    // Signal to a watch tower that polling should be attempted again.
    error PollTryNextBlock(string reason);
    // Signal to a watch tower that polling should be attempted again at a specific block number.
    error PollTryAtBlock(uint256 blockNumber, string reason);
    // Signal to a watch tower that polling should be attempted again at a specific epoch (unix timestamp).
    error PollTryAtEpoch(uint256 timestamp, string reason);
    // Signal to a watch tower that the conditional order should not be polled again (delete).
    error PollNever(string reason);

    /**
     * @dev This struct is used to uniquely identify a conditional order for an owner.
     *      H(handler || salt || staticInput) **MUST** be unique for an owner.
     */
    struct ConditionalOrderParams {
        IConditionalOrder handler;
        bytes32 salt;
        bytes staticInput;
    }
}

/**
 * @title Conditional Order Generator Interface
 * @author CoW Protocol Developers
 */
interface IConditionalOrderGenerator is IConditionalOrder {
    /**
     * @dev This event is emitted when a new conditional order is created.
     * @param owner the address that has created the conditional order
     * @param params the address / salt / data of the conditional order
     */
    event ConditionalOrderCreated(address indexed owner, IConditionalOrder.ConditionalOrderParams params);
}
