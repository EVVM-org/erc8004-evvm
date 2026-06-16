// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {UserValidator} from "../src/UserValidator.sol";

/**
 * @title DeployUserValidator
 * @notice Deployment script for UserValidator (Type 2)
 * @dev ERC-8004 balanceOf check validator.
 *
 *      Environment variables:
 *      - ADMIN (required): Admin address for the validator
 *      - IDENTITY_REGISTRY (optional): Override auto-detected registry address
 *
 *      Usage:
 *      ADMIN=0x... forge script script/DeployUserValidator.s.sol --broadcast
 */
contract DeployUserValidator is Script {
    /// @notice ERC-8004 Identity Registry on all mainnets
    address constant MAINNET_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;

    /// @notice ERC-8004 Identity Registry on all testnets
    address constant TESTNET_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;

    function run() public {
        address admin = vm.envAddress("ADMIN");

        require(admin != address(0), "ADMIN cannot be zero address");

        uint256 chainId = block.chainid;
        address registry = _getIdentityRegistry(chainId);

        console.log("Deploying UserValidator");
        console.log("Chain ID:", chainId);
        console.log("Admin:", admin);
        console.log("Identity Registry:", registry);

        vm.startBroadcast();

        UserValidator validator = new UserValidator(admin, registry);
        console.log("UserValidator deployed at:", address(validator));

        vm.stopBroadcast();
    }

    /**
     * @notice Returns the Identity Registry address for the given chain ID
     * @dev Can be overridden with IDENTITY_REGISTRY env var
     */
    function _getIdentityRegistry(uint256 chainId) internal view returns (address) {
        if (vm.envOr("IDENTITY_REGISTRY", address(0)) != address(0)) {
            return vm.envAddress("IDENTITY_REGISTRY");
        }

        if (_isMainnet(chainId)) {
            return MAINNET_REGISTRY;
        }

        if (_isTestnet(chainId)) {
            return TESTNET_REGISTRY;
        }

        revert("Unknown chain ID. Set IDENTITY_REGISTRY env var to override.");
    }

    function _isMainnet(uint256 chainId) internal pure returns (bool) {
        return chainId == 1 ||
               chainId == 10 ||
               chainId == 56 ||
               chainId == 100 ||
               chainId == 137 ||
               chainId == 196 ||
               chainId == 2741 ||
               chainId == 8453 ||
               chainId == 167000 ||
               chainId == 42161 ||
               chainId == 42220 ||
               chainId == 43114 ||
               chainId == 5000 ||
               chainId == 1088 ||
               chainId == 534352 ||
               chainId == 59144;
    }

    function _isTestnet(uint256 chainId) internal pure returns (bool) {
        return chainId == 97 ||
               chainId == 296 ||
               chainId == 44787 ||
               chainId == 1946 ||
               chainId == 11155111 ||
               chainId == 11155420 ||
               chainId == 80002 ||
               chainId == 84532 ||
               chainId == 421614 ||
               chainId == 43113 ||
               chainId == 595581 ||
               chainId == 5003 ||
               chainId == 59902 ||
               chainId == 534351;
    }
}
