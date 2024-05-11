// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, Vm, console} from "forge-std/Test.sol";
import {ERC1967Factory} from "src/ERC1967Factory.sol";

contract ERC1967FactoryTest is Test {
    ERC1967Factory public factory;
    address msgSender = makeAddr("msgSender");
    address implementation = makeAddr("implementation");
    address admin = makeAddr("admin");
    bytes32 salt = keccak256("random-salt");

    function setUp() external virtual {
        factory = new ERC1967Factory();
    }

    function testChangeAdmin() public {
        address proxy = factory.deployDeterministic(implementation, admin, salt);

        address newAdmin = makeAddr("newAdmin");
        vm.prank(admin);
        factory.changeAdmin(proxy, newAdmin);

        assertEq(factory.adminOf(proxy), newAdmin, "Admin should be changed");
    }

    function testImplementationForwarding() public {
        implementation = address(new TestImplementation());

        address proxy = factory.deployDeterministic(implementation, admin, salt);

        bytes32 testValue = bytes32("hello");
        vm.expectCall(implementation, abi.encodeWithSelector(TestImplementation.echo.selector, testValue));
        bytes32 output = TestImplementation(proxy).echo(testValue);
        assertEq(output, testValue, "Implementation should echo the input");
    }

    function testUpgradeTo() public {
        implementation = address(new TestImplementation());
        address proxy = factory.deployDeterministic(implementation, admin, salt);

        // Check the test is configured correctly
        bytes32 testValue = bytes32("hello");
        bytes32 output = TestImplementation(proxy).echo(testValue);
        assertEq(output, testValue, "Implementation should be correct");

        address newImplementation = address(new TestUpgradedImplementation());
        vm.prank(admin);
        factory.upgrade(proxy, newImplementation);

        // Check the upgrade was successful
        output = TestUpgradedImplementation(proxy).echo(testValue);
        assertEq(output, bytes32("upgraded"), "Implementation should be upgraded");
    }

    function testDeterminsticDeployment() public {
        // Before deployment, predict the address
        vm.prank(msgSender);
        address predicted = factory.predictDeterministicAddress(salt);
        bytes memory code = predicted.code;
        assertEq(code.length, 0, "Predicted address should be empty");

        vm.prank(msgSender);
        address proxy = factory.deployDeterministic(implementation, admin, salt);

        // After deployment, the address should be the same
        assertEq(proxy, predicted, "Proxy address should be deterministic");
    }
}

contract TestImplementation {
    function echo(bytes32 value) external pure returns (bytes32) {
        return value;
    }
}

contract TestUpgradedImplementation {
    function echo(bytes32) external pure returns (bytes32) {
        return bytes32("upgraded");
    }
}
