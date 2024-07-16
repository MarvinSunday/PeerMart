// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/Escrow.sol";

contract DeployEscrow is Script {
    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Replace these with your admin and token addresses
        address admin = 0x617eca02EE345f7dB08A941f22cef7b284484e2e;
        address receiver = msg.sender;
        address tokenAddress = 0xaA12683f2e7D78f852525a843c33d9540aD1aAF2;
        // address tokenAddress = 0x5E6132634dfA87D5D8968F0F7F2F4027ef60c4eF;

        // Deploy the contract
        Escrow escrow = new Escrow(admin, receiver, tokenAddress);

        // Log the deployed contract address
        console.log("Escrow deployed at:", address(escrow));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
