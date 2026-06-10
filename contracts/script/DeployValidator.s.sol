// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {UserValidatorManual} from "../src/UserValidatorManual.sol";
import {UserValidator} from "../src/UserValidator.sol";
import {UserValidatorPreRegistrated} from "../src/UserValidatorPreRegistrated.sol";

/**
 * @title DeployValidator
 * @notice Deployment script for EVVM user validators
 * @dev Supports three validator types via VALIDATOR_TYPE env var:
 *
 *      Type 1: UserValidatorManual - Manual whitelist (admin manages allowed users)
 *      Type 2: UserValidator - ERC-8004 balanceOf check (owns at least one agent)
 *      Type 3: UserValidatorPreRegistrated - Pre-registration + signature authorization
 *
 *      Environment variables:
 *      - VALIDATOR_TYPE (required): 1, 2, or 3
 *      - ADMIN (required): Admin address for the validator
 *      - EVVM_AUTHORIZER (required for type 3): Address that signs agent authorizations
 *      - IDENTITY_REGISTRY (optional): Override auto-detected registry address
 *
 *      Usage:
 *      VALIDATOR_TYPE=1 ADMIN=0x... forge script script/DeployValidator.s.sol --broadcast
 *      VALIDATOR_TYPE=2 ADMIN=0x... forge script script/DeployValidator.s.sol --broadcast
 *      VALIDATOR_TYPE=3 ADMIN=0x... EVVM_AUTHORIZER=0x... forge script script/DeployValidator.s.sol --broadcast
 */
contract DeployValidator is Script {
    /// @notice ERC-8004 Identity Registry on all mainnets
    address constant MAINNET_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;

    /// @notice ERC-8004 Identity Registry on all testnets
    address constant TESTNET_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;

    function run() public {
        uint256 validatorType = vm.envUint("VALIDATOR_TYPE");
        address admin = vm.envAddress("ADMIN");

        require(validatorType >= 1 && validatorType <= 3, "VALIDATOR_TYPE must be 1, 2, or 3");
        require(admin != address(0), "ADMIN cannot be zero address");

        uint256 chainId = block.chainid;
        console.log("Deploying validator type:", validatorType);
        console.log("Chain ID:", chainId);
        console.log("Admin:", admin);

        vm.startBroadcast();

        if (validatorType == 1) {
            _deployManual(admin);
        } else if (validatorType == 2) {
            address registry = _getIdentityRegistry(chainId);
            console.log("Identity Registry:", registry);
            _deployBalanceOf(admin, registry);
        } else {
            address registry = _getIdentityRegistry(chainId);
            address authorizer = vm.envAddress("EVVM_AUTHORIZER");
            require(authorizer != address(0), "EVVM_AUTHORIZER cannot be zero address");
            console.log("Identity Registry:", registry);
            console.log("EVVM Authorizer:", authorizer);
            _deployPreRegistered(admin, registry, authorizer);
        }

        vm.stopBroadcast();
    }

    function _deployManual(address admin) internal {
        UserValidatorManual validator = new UserValidatorManual(admin);
        console.log("UserValidatorManual deployed at:", address(validator));
    }

    function _deployBalanceOf(address admin, address registry) internal {
        UserValidator validator = new UserValidator(admin, registry);
        console.log("UserValidator deployed at:", address(validator));
    }

    function _deployPreRegistered(address admin, address registry, address authorizer) internal {
        UserValidatorPreRegistrated validator = new UserValidatorPreRegistrated(admin, registry, authorizer);
        console.log("UserValidatorPreRegistrated deployed at:", address(validator));
    }

    /**
     * @notice Returns the Identity Registry address for the given chain ID
     * @dev Can be overridden with IDENTITY_REGISTRY env var
     * @param chainId The chain ID to look up
     * @return The Identity Registry address
     */
    function _getIdentityRegistry(uint256 chainId) internal view returns (address) {
        // Allow override via environment variable
        if (vm.envOr("IDENTITY_REGISTRY", address(0)) != address(0)) {
            return vm.envAddress("IDENTITY_REGISTRY");
        }

        // Mainnets - all use the same registry address
        if (_isMainnet(chainId)) {
            return MAINNET_REGISTRY;
        }

        // Testnets - all use the same registry address
        if (_isTestnet(chainId)) {
            return TESTNET_REGISTRY;
        }

        revert("Unknown chain ID. Set IDENTITY_REGISTRY env var to override.");
    }

    /**
     * @notice Checks if the chain ID is a known mainnet
     */
    function _isMainnet(uint256 chainId) internal pure returns (bool) {
        return chainId == 1 ||        // Ethereum
               chainId == 10 ||       // Optimism
               chainId == 56 ||       // BSC
               chainId == 100 ||      // Gnosis
               chainId == 137 ||      // Polygon
               chainId == 196 ||      // XLayer
               chainId == 2741 ||     // Abstract
               chainId == 8453 ||     // Base
               chainId == 167000 ||   // Taiko
               chainId == 42161 ||    // Arbitrum One
               chainId == 42220 ||    // Celo
               chainId == 43114 ||    // Avalanche
               chainId == 5000 ||     // Mantle
               chainId == 1088 ||     // Metis
               chainId == 534352 ||   // Scroll
               chainId == 59144;      // Linea
    }

    /**
     * @notice Checks if the chain ID is a known testnet
     */
    function _isTestnet(uint256 chainId) internal pure returns (bool) {
        return chainId == 97 ||        // BSC Testnet
               chainId == 296 ||       // Hedera Testnet
               chainId == 44787 ||     // Celo Alfajores
               chainId == 1946 ||      // Soneium Minato
               chainId == 11155111 ||  // Ethereum Sepolia
               chainId == 11155420 ||  // Optimism Sepolia
               chainId == 80002 ||     // Polygon Amoy
               chainId == 84532 ||     // Base Sepolia
               chainId == 421614 ||    // Arbitrum Sepolia
               chainId == 43113 ||     // Avalanche Fuji
               chainId == 595581 ||    // Linea Sepolia
               chainId == 5003 ||      // Mantle Sepolia
               chainId == 59902 ||     // Metis Sepolia
               chainId == 534351;      // Scroll Sepolia
    }
}
