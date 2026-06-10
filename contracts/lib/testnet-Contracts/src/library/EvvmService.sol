// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;
/**
 * @title EVVM Service Base Contract
 * @author Mate Labs
 * @notice Abstract base contract for building EVVM services with payment, staking, and nonce management
 * @dev Inherits StakingServiceUtils and CoreExecution. Signatures validated via Core.sol.
 */

import {
    CoreExecution
} from "@evvm/testnet-contracts/library/utils/service/CoreExecution.sol";
import {
    StakingServiceUtils
} from "@evvm/testnet-contracts/library/utils/service/StakingServiceUtils.sol";

abstract contract EvvmService is CoreExecution, StakingServiceUtils {
    /// @dev Thrown when signature validation fails
    error InvalidServiceSignature();

    /**
     * @notice Initializes EVVM service with core contract references
     * @param coreAddress Address of Core.sol contract
     * @param stakingAddress Address of Staking.sol contract
     */
    constructor(
        address coreAddress,
        address stakingAddress
    ) StakingServiceUtils(stakingAddress) CoreExecution(coreAddress) {}

    /**
     * @notice Gets unique EVVM instance identifier for signature validation
     * @return Unique EVVM instance identifier
     */
    function getEvvmID() public view returns (uint256) {
        return core.getEvvmID();
    }

    /**
     * @notice Gets Principal Token (MATE) address
     * @return Address of Principal Token (MATE)
     */
    function getPrincipalTokenAddress() public view returns (address) {
        return core.getPrincipalTokenAddress();
    }
}
