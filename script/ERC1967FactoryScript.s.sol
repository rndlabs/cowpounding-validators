// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Factory} from "src/ERC1967Factory.sol";

contract ERC1967FactoryScript is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        new ERC1967Factory();
    }
}
