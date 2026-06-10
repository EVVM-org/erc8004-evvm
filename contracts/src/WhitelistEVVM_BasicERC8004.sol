// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title WhitelistEVVM_BasicERC8004
 * @notice Example 1: minimal EVVM whitelist using the official ERC-8004 Identity Registry.
 *
 * Goal:
 * - EVVM calls canExecute(user).
 * - The whitelist returns true if `user` owns at least one ERC-8004 agent.
 *
 * What this example proves:
 * - With only an address, an onchain contract can check:
 *      address -> does it own registered agents?  yes, using balanceOf(address) > 0
 *      address -> how many agents?               yes, using balanceOf(address)
 *
 * What this example does NOT prove:
 * - It cannot list the agentIds owned by `user`, because plain ERC-721 does not
 *   require token enumeration by owner. That requires ERC721Enumerable, a custom
 *   reverse lookup, events/indexers, or a pre-registration flow.
 *
 * Registry:
 * - Uses the real ERC-8004 Identity Registry on Ethereum Mainnet by default:
 *   0x8004A169FB4a3325136EB29fA0ceB6D2e539a432
 *
 * Important:
 * - This contract must run on the same chain where that registry exists.
 * - If EVVM runs elsewhere, it needs a native read mechanism, mirror, oracle,
 *   bridge, or equivalent same-chain deployment of the official registry.
 */

interface IERC721BalanceOf {
    function balanceOf(address owner) external view returns (uint256);
}

contract WhitelistEVVM_BasicERC8004 {
    /// @notice Official ERC-8004 Identity Registry on Ethereum Mainnet.
    address public constant ETHEREUM_MAINNET_ERC8004_IDENTITY_REGISTRY =
        0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;

    IERC721BalanceOf public immutable identityRegistry;

    error ZeroAddress();

    /**
     * @notice Deploy using the official Ethereum Mainnet registry by passing address(0).
     * @param identityRegistry_ ERC-8004 Identity Registry address. Use address(0) for Mainnet official.
     */
    constructor(address identityRegistry_) {
        address registry = identityRegistry_ == address(0)
            ? ETHEREUM_MAINNET_ERC8004_IDENTITY_REGISTRY
            : identityRegistry_;

        if (registry == address(0)) {
            revert ZeroAddress();
        }

        identityRegistry = IERC721BalanceOf(registry);
    }

    /**
     * @notice EVVM-facing binary check.
     * @param user Address trying to execute through the EVVM.
     * @return allowed True if user owns one or more ERC-8004 agents.
     */
    function canExecute(address user) external view returns (bool allowed) {
        if (user == address(0)) {
            return false;
        }

        try identityRegistry.balanceOf(user) returns (uint256 balance) {
            return balance > 0;
        } catch {
            return false;
        }
    }

    /**
     * @notice Helper for demos/UI.
     * @dev This gives the count, but not the agentIds.
     */
    function agentBalanceOf(address user) external view returns (uint256 balance) {
        if (user == address(0)) {
            return 0;
        }

        try identityRegistry.balanceOf(user) returns (uint256 result) {
            return result;
        } catch {
            return 0;
        }
    }
}
