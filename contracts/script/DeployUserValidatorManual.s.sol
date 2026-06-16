// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {UserValidatorManual} from "../src/UserValidatorManual.sol";

/**
 * @title DeployUserValidatorManual
 * @notice Deployment script for UserValidatorManual (Type 1)
 * @dev Simple manual whitelist validator.
 *
 *      Environment variables:
 *      - ADMIN (required): Admin address for the validator
 *
 *      Usage:
 *      ADMIN=0x... forge script script/DeployUserValidatorManual.s.sol --broadcast
 */
contract DeployUserValidatorManual is Script {
    function run() public {
        address admin = vm.envAddress("ADMIN");

        require(admin != address(0), "ADMIN cannot be zero address");

        console.log("Deploying UserValidatorManual");
        console.log("Admin:", admin);

        vm.startBroadcast();

        UserValidatorManual validator = new UserValidatorManual(admin);
        console.log("UserValidatorManual deployed at:", address(validator));

        vm.stopBroadcast();
    }
}
