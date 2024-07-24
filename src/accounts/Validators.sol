// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {IDeposit} from "src/interfaces/IDeposit.sol";
import {IERC677} from "src/interfaces/IERC677.sol";
import {IConditionalOrder} from "src/interfaces/IConditionalOrder.sol";
import {IERC1271} from "src/interfaces/IERC1271.sol";
import {ISettlement} from "src/interfaces/ISettlement.sol";
import {IAggregatorV3} from "src/interfaces/IAggregatorV3.sol";
import {ValidatorStorage} from "src/libraries/ValidatorStorage.sol";
import {GPv2Order} from "src/libraries/GPv2Order.sol";

contract Validators is Ownable, ValidatorStorage, IERC1271 {
    using GPv2Order for GPv2Order.Data;
    // --- constants ---

    WETH public constant weth = WETH(payable(0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d));
    IERC677 public constant gno = IERC677(0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb);
    IDeposit public constant gbcDeposit = IDeposit(0x0B98057eA310F4d31F2a452B414647007d1645d9);
    IAggregatorV3 public constant oracle = IAggregatorV3(0x22441d81416430A54336aB28765abd31a792Ad37);

    bytes4 private constant _ERC1271_INVALID = 0xffffffff;
    uint256 private constant MAX_ORDER_DURATION = 1 hours;

    // --- errors ---

    error FailedToDepositValidator();
    error OrderDoesNotMatchMessageHash(bytes32 calculated, bytes32 provider);

    // --- initialization ---

    /**
     * @notice Initialize the contract with required state
     */
    function initialize(address _owner, bytes32 _appData, address settlement) external {
        _initializeOwner(_owner);

        State storage state = _state();
        state.appData = _appData();
        state.domainSeparator = GPv2Settlement(settlement).domainSeparator();

        emit IConditionalOrder.ConditionalOrderCreated(_owner, IConditionalOrder.ConditionalOrderParams(this, 0, ""));
    }

    // --- auth ---

    /**
     * @notice Assert that double-initialization is not possible
     */
    function _guardInitializeOwner() internal pure virtual override returns (bool guard) {
        return true;
    }

    // --- cow protocol signing ---

    function isValidSignature(bytes32 _hash, bytes calldata signature) external view returns (bytes4) {
        GPv2Order.Data memory order = abi.decode(signature, (GPv2Order.Data));

        bytes32 orderHash = order.hash(_state().domainSeparator);
        if (orderHash != _hash) {
            revert OrderDoesNotMatchMessageHash(orderHash, _hash);
        }

        verify(order);

        // A signature is valid according to ERC-1271 if this function returns
        // its selector as the so-called "magic value".
        return IERC1271.isValidSignature.selector;
    }

    /**
     * @notice Check that the input order is admissible for automatically restaking
     * earnt validator yield.
     * @param order `GPv2Order.Data` of a discrete order to be verified.
     */
    function verify(GPv2Order.Data memory order) public view {
        // An order is only valid if:
        // - The native eth balance of this contract is zero (the hook has been called)
        // - The withdrawable amount from GBC is zero (the hook has been called)
        // - The GNO balance of this contract is at least 1 GNO
        // - The WETH balance of this contract is at least 1 WETH
        if (address(this).balance > 0) {
            revert IConditionalOrder.OrderNotValid("wrapAll hook not called");
        }
        if (gbcDeposit.withdrawableAmount(address(this)) > 0) {
            revert IConditionalOrder.OrderNotValid("gbcDeposit claimAll hook not called");
        }
        if (weth.balanceOf(address(this)) < 1e18) {
            revert IConditionalOrder.OrderNotValid("insufficient weth balance");
        }
        if (gno.balanceOf(address(this)) < 1e18) {
            revert IConditionalOrder.OrderNotValid("insufficient gno balance");
        }

        // -- order parameters ---

        // only sell WXDAI (weth)
        if (order.sellToken != weth) {
            revert IConditionalOrder.OrderNotValid("invalid sell token");
        }

        // ensure that the sell amount is bounded between 1 WETH and the WETH balance
        if (order.sellAmount < 1e18 || order.sellAmount > weth.balanceOf(address(this))) {
            revert IConditionalOrder.OrderNotValid("invalid sell amount");
        }

        // only buy GNO
        if (order.buyToken != gno) {
            revert IConditionalOrder.OrderNotValid("invalid buy token");
        }

        // --- slippage checking ---
        if (!_checkSlippage(order.sellAmount, order.buyAmount)) {
            revert IConditionalOrder.OrderNotValid("slippage too high");
        }

        // Ensure that the receiver is the same as this contract.
        if (order.receiver != GPv2Order.RECEIVER_SAME_AS_OWNER) {
            revert IConditionalOrder.OrderNotValid("receiver must be zero address");
        }

        // // We add a maximum duration to avoid spamming the orderbook and force
        // // an order refresh if the order is old.
        if (order.validTo > block.timestamp + MAX_ORDER_DURATION) {
            revert IConditionalOrder.OrderNotValid("validity too far in the future");
        }

        // Check that the appData matches what we were initialized with.
        if (order.appData != _state().appData) {
            revert IConditionalOrder.OrderNotValid("invalid appData");
        }

        // CoW Protocol now treats everything as a limit order, therefore the fee
        // amount must be zero.
        if (order.feeAmount != 0) {
            revert IConditionalOrder.OrderNotValid("fee amount must be zero");
        }

        // enforce only sell orders
        if (order.kind != GPv2Order.KIND_SELL) {
            revert IConditionalOrder.OrderNotValid("kind must be sell");
        }

        // ensure orders are fill-or-kill
        if (order.partiallyFillable) {
            revert IConditionalOrder.OrderNotValid("partiallyFillable must be false");
        }

        // enusre that tokens are taken from and deposited to our ERC20 balances
        if (order.buyTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert IConditionalOrder.OrderNotValid("buyTokenBalance must be erc20");
        }
        if (order.sellTokenBalance != GPv2Order.BALANCE_ERC20) {
            revert IConditionalOrder.OrderNotValid("sellTokenBalance must be erc20");
        }
    }

    /**
     * @notice The order returned by this function is the order that needs to be
     * executed for the price on this AMM to match that of the reference pair.
     * @param tradingParams the trading parameters of all discrete orders cut
     * from this AMM
     * @return order the tradeable order for submission to the CoW Protocol API
     */
    function getTradeableOrder() public view returns (GPv2Order.Data memory order) {
        uint256 sellAmount = address(this).balance + weth.balanceOf(address(this));
        // Tell the watch tower to try again later if the contract does not have
        // more than 1 WETH or GNO.
        if (sellAmount < 1e18) {
            revert IConditionalOrder.PollTryAtEpoch(block.timestamp + 1 hours, "insufficient weth balance");
        }
        if (gbcDeposit.withdrawableAmount(address(this)) + gno.balanceOf(address(this)) < 1e18) {
            revert IConditionalOrder.PollTryAtEpoch(block.timestamp + 1 hours, "insufficient gno balance");
        }

        // --- on-chain price feed ---

        // Get the latest price data from the Chainlink aggregator
        (, int256 price, , uint256 updatedAt,) = oracle.latestRoundData();

        // Ensure the price is positive
        if (price <= 0) {
            revert IConditionalOrder.PollTryAtEpoch(block.timestamp + 1 hours, "invalid price feed");
        }

        // ensure that the price is up-to-date
        if (block.timestamp - updatedAt > 3 hours) {
            revert IConditionalOrder.PollTryAtEpoch(block.timestamp + 1 hours, "price is outdated");
        }

        // Normalize the price to 18 decimal places
        uint256 normalizedPrice = uint256(price) * 10**10; // 8 decimal places to 18 decimal places
        uint256 buyAmount = (sellAmount * 10**18) / normalizedPrice;
        uint256 buyAmountLessSlippage = (buyAmount * 97) / 100;

        order = GPv2Order.Data(
            ERC20(address(weth)),
            gno,
            GPv2Order.RECEIVER_SAME_AS_OWNER,
            sellAmount,
            buyAmountLessSlippage,
            Utils.validToBucket(MAX_ORDER_DURATION),
            _state().appData,
            0,
            GPv2Order.KIND_SELL,
            false, // partiallyFillable as fill or kill
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );
    }

    /**
     * @notice This function exists to let the watchtower off-chain service
     * automatically create AMM orders and post them on the orderbook. It
     * outputs an order for the input AMM together with a valid signature.
     * @dev Some parameters are unused as they refer to features of
     * ComposableCoW that aren't implemented in this contract. They are still
     * needed to let the watchtower interact with this contract in the same way
     * as ComposableCoW.
     * @param amm owner of the order.
     * @param params `ConditionalOrderParams` for the order; precisely, the
     * handler must be this contract, the salt can be any value, and the static
     * input must be the current trading parameters of the AMM.
     * @return order discrete order for submitting to CoW Protocol API
     * @return signature for submitting to CoW Protocol API
     */
    function getTradeableOrderWithSignature(
        address, // owner
        IConditionalOrder.ConditionalOrderParams calldata, // params
        bytes calldata, // offchainInput
        bytes32[] calldata // proof
    ) external view returns (GPv2Order.Data memory order, bytes memory signature) {
        order = getTradeableOrder();
        signature = abi.encode(order);
    }

    // --- hooks ---

    /**
     * @notice Permissionlesslyl allow all xdai to be wrapped
     */
    function wrapAll() public {
        weth.deposit{value: address(this).balance}();
    }

    /**
     * @notice Permissionlessly allow all withdrawals to be claimed
     */
    function claimAll() public {
        gbcDeposit.claimWithdrawal(address(this));
    }

    /**
     * @notice Permissionlessly deposit a validator
     */
    function depositValidator() external {
        (bytes32 depositData, Validator memory validator) = next();

        if (
            !gno.transferAndCall(
                address(gbcDeposit),
                1e18,
                abi.encodePacked(withdrawalCredentials(), validator.pubkey, validator.signature, depositData)
            )
        ) {
            revert FailedToDepositValidator();
        }
    }

    // --- helpers ---

    function _checkSlippage(uint256 sellAmount, uint256 buyAmount) internal view returns (bool) {
        // Get the latest price data from the Chainlink aggregator
        (, int256 price, , uint256 updatedAt,) = priceFeed.latestRoundData();

        // Ensure the price is positive
        if (price <= 0) {
            revert IConditionalOrder.OrderNotValid("Invalid price feed");
        }

        // ensure that the price is up-to-date
        if (block.timestamp - updatedAt > 3 hours) {
            revert IConditionalOrder.OrderNotValid("price is outdated");
        }

        // Normalize the price to 18 decimal places
        uint256 normalizedPrice = uint256(price) * 10**10; // 8 decimal places to 18 decimal places

        // Calculate the expected buy amount based on the normalized price
        uint256 expectedBuyAmount = (sellAmount * 10**18) / normalizedPrice;

        // Calculate the lower bound for slippage (5% tolerance)
        uint256 lowerBound = (expectedBuyAmount * 95) / 100;

        // Check if the actual buy amount is within the acceptable range
        return buyAmount >= lowerBound;
    }

    /**
     * @notice Get the withdrawal credentials that this contract is bound to
     * @return _withdrawalCredentials The withdrawal credentials for depositing
     */
    function withdrawalCredentials() public view returns (bytes32 _withdrawalCredentials) {
        assembly {
            _withdrawalCredentials := or(shl(248, 1), address())
        }
    }

    /**
     * @notice Handle any native asset received by the contract
     */
    receive() external payable {}
}
