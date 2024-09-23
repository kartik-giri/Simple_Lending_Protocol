// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Protocol} from "../src/Protocol.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

contract ProtocolScript is Script {
    Protocol public protocol;
    MockUSDC public mockUSDC;


    function run() public returns(address, address) {
        vm.startBroadcast();

        mockUSDC = new MockUSDC();
        protocol = new Protocol(address(mockUSDC));

        vm.stopBroadcast();
        return (address(mockUSDC), address(protocol));
    }
}
