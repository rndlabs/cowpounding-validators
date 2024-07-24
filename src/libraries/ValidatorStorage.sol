// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {EnumerableSetLib} from "solady/utils/EnumerableSetLib.sol";

abstract contract ValidatorStorage is Ownable {
    using EnumerableSetLib for EnumerableSetLib.Bytes32Set;

    struct State {
        bytes32 appData;
        bytes32 domainSeparator;
        mapping(bytes32 => Validator) validators;
        EnumerableSetLib.Bytes32Set validatorSet;
    }

    struct Validator {
        bytes pubkey;
        bytes signature;
    }

    bytes32 internal constant STATE_SLOT = keccak256("validators.storage");

    function _state() internal pure returns (State storage state) {
        bytes32 stateSlot = STATE_SLOT;
        assembly {
            state.slot := stateSlot
        }
    }

    // --- validator credentials ---

    error EmptyValidatorSet();
    error ValidatorDoesNotExist();
    error ValidatorAlreadyExists();

    function next() internal returns (bytes32 depositData, Validator memory validator) {
        State storage state = _state();
        if (state.validatorSet.length() == 0) {
            revert EmptyValidatorSet();
        }
        depositData = state.validatorSet.at(0);
        validator = state.validators[depositData];

        _removeValidator(state, depositData);
    }

    function addValidator(bytes32 depositData, bytes calldata pubkey, bytes calldata signature) external onlyOwner {
        State storage state = _state();
        if (state.validatorSet.contains(depositData)) {
            revert ValidatorAlreadyExists();
        }

        _addValidator(state, depositData, pubkey, signature);
    }

    function addValidators(bytes32[] calldata depositData, bytes[] calldata pubkeys, bytes[] calldata signatures)
        external
        onlyOwner
    {
        State storage state = _state();
        for (uint256 i = 0; i < depositData.length;) {
            if (state.validatorSet.contains(depositData[i])) {
                revert ValidatorAlreadyExists();
            }

            _addValidator(state, depositData[i], pubkeys[i], signatures[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _addValidator(State storage state, bytes32 depositData, bytes memory pubkey, bytes memory signature)
        internal
    {
        state.validators[depositData] = Validator(pubkey, signature);
        state.validatorSet.add(depositData);
    }

    function removeValidator(bytes32 depositData) external onlyOwner {
        State storage state = _state();
        if (!state.validatorSet.contains(depositData)) {
            revert ValidatorDoesNotExist();
        }

        _removeValidator(state, depositData);
    }

    function removeValidators(bytes32[] calldata depositData) external onlyOwner {
        State storage state = _state();
        for (uint256 i = 0; i < depositData.length;) {
            if (!state.validatorSet.contains(depositData[i])) {
                revert ValidatorDoesNotExist();
            }

            _removeValidator(state, depositData[i]);

            unchecked {
                ++i;
            }
        }
    }

    function _removeValidator(State storage state, bytes32 depositData) internal {
        delete state.validators[depositData];
        state.validatorSet.remove(depositData);
    }

    function getValidator(bytes32 depositData) external view returns (Validator memory) {
        State storage state = _state();
        return state.validators[depositData];
    }

    function getValidators() external view returns (bytes32[] memory, Validator[] memory) {
        State storage state = _state();
        bytes32[] memory depositDatas = new bytes32[](state.validatorSet.length());
        Validator[] memory validators = new Validator[](state.validatorSet.length());

        for (uint256 i = 0; i < state.validatorSet.length();) {
            bytes32 depositData = state.validatorSet.at(i);
            depositDatas[i] = depositData;
            validators[i] = state.validators[depositData];

            unchecked {
                ++i;
            }
        }

        return (depositDatas, validators);
    }
}
