// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, Vm, console} from "forge-std/Test.sol";
import {ERC1967Factory} from "src/ERC1967Factory.sol";
import {Validators} from "src/accounts/Validators.sol";
import {ValidatorStorage} from "src/libraries/ValidatorStorage.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {WETH} from "solady/tokens/WETH.sol";

contract ValidatorsTest is Test {
    ERC1967Factory public factory;

    address msgSender = makeAddr("proxy-owner");
    address admin = msgSender;
    bytes32 salt = keccak256("some-salt");
    Validators implementation;
    Validators account;

    function setUp() external virtual {
        // Deploy the ERC1967Factory
        factory = new ERC1967Factory();

        // Deploy the implementation contract
        implementation = new Validators();

        // Deploy the account contract
        vm.prank(msgSender);
        account = Validators(
            payable(
                factory.deployDeterministicAndCall(
                    address(implementation), admin, salt, abi.encodeCall(Validators.initialize, (msgSender))
                )
            )
        );
    }

    function testNoDoubleInitialize() public {
        // Try to initialize the account contract again
        vm.expectRevert(abi.encodeWithSelector(Ownable.AlreadyInitialized.selector));
        account.initialize(makeAddr("malicious-user"));
    }

    function testAuth() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        account.addValidator(bytes32("some deposit data"), "some pubkey", "some signature");

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        account.addValidators(new bytes32[](1), new bytes[](1), new bytes[](1));

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        account.removeValidator(bytes32("some validator"));

        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        account.removeValidators(new bytes32[](1));
    }

    function testWrapAll() public {
        WETH weth = WETH(payable(account.weth()));
        uint256 balanceNative = address(account).balance;
        uint256 balanceWeth = weth.balanceOf(address(account));

        account.wrapAll();

        assertEq(address(account).balance, 0);
        assertEq(weth.balanceOf(address(account)), balanceNative + balanceWeth);
    }

    function testClaimAll() public {
        ERC20 gno = ERC20(address(account.gno()));
        uint256 balanceGno = gno.balanceOf(address(account));
        uint256 claimable = account.gbcDeposit().withdrawableAmount(address(account));

        account.claimAll();

        assertEq(gno.balanceOf(address(account)), balanceGno + claimable);
        assertEq(account.gbcDeposit().withdrawableAmount(address(account)), 0);
    }

    function testRevertWhenEmpty() public {
        vm.expectRevert(abi.encodeWithSelector(ValidatorStorage.EmptyValidatorSet.selector));
        account.depositValidator();
    }

    function testRevertWhenValidatorAlreadyExists() public {
        vm.startPrank(msgSender);
        bytes32 depositData = bytes32("deposit-data");
        bytes memory pubkey = abi.encode("some-key");
        bytes memory signature = abi.encode("some-signature");
        account.addValidator(depositData, pubkey, signature);

        vm.expectRevert(abi.encodeWithSelector(ValidatorStorage.ValidatorAlreadyExists.selector));
        account.addValidator(depositData, pubkey, signature);

        bytes32[] memory depositDatas = new bytes32[](1);
        depositDatas[0] = depositData;
        bytes[] memory pubkeys = new bytes[](1);
        pubkeys[0] = pubkey;
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = signature;

        vm.expectRevert(abi.encodeWithSelector(ValidatorStorage.ValidatorAlreadyExists.selector));
        account.addValidators(depositDatas, pubkeys, signatures);
    }

    function testRevertWhenValidatorDoesNotExist() public {
        vm.startPrank(msgSender);

        vm.expectRevert(abi.encodeWithSelector(ValidatorStorage.ValidatorDoesNotExist.selector));
        account.removeValidator(bytes32("validator-that-does-not-exist"));

        vm.expectRevert(abi.encodeWithSelector(ValidatorStorage.ValidatorDoesNotExist.selector));
        account.removeValidators(new bytes32[](1));
    }

    function testCreateValidators() public {
        account.wrapAll();
        account.claimAll();

        ERC20 gno = ERC20(address(account.gno()));

        // get the balance of the account's gno token given it has claimed
        uint256 balance = gno.balanceOf(address(account));

        vm.prank(msgSender);
        // the below needs generation of deposit data
        account.addValidator(
            bytes32("some-deposit-data"),
            hex"some-data",
            hex"some-data"
        );

        address tempHolding = makeAddr("temp-holding");
        uint256 topUp = 1e18 - balance;
        deal(address(gno), tempHolding, topUp);
        vm.prank(tempHolding);
        gno.transfer(address(account), topUp);

        account.depositValidator();

        assertEq(gno.balanceOf(address(account)), 0);

        (bytes32[] memory depositDatas, Validators.Validator[] memory validators) = account.getValidators();
        assertEq(depositDatas.length, 0);
        assertEq(validators.length, 0);
    }
}
