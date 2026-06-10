// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense
pragma solidity ^0.8.0;

/// @title UserValidatorManual
/// @notice Simple EVVM user validator with manual whitelist management
/// @dev This contract implements a basic allowlist pattern where an admin can
/// manually add or remove authorized users. Unlike the ERC-8004 based validators,
/// this requires direct admin intervention for each user.
contract UserValidatorManual {
    /// @notice Thrown when a non-admin attempts to call an admin-only function
    error UserNotAllowed();

    /// @notice Administrative address with permission to manage the whitelist
    address admin;

    /// @notice Mapping of user addresses to their authorization status
    /// @dev True means the user is allowed to execute through the EVVM
    mapping(address => bool) private allowedUsers;

    /// @notice Restricts function access to the admin address only
    /// @dev Reverts with UserNotAllowed if msg.sender is not the admin
    modifier onlyAdmin() {
        if (msg.sender != admin) revert UserNotAllowed();
        _;
    }

    /// @notice Creates a new UserValidatorManual instance with the specified admin
    /// @param _initialAdmin The address that will have admin privileges for whitelist management
    constructor(address _initialAdmin) {
        admin = _initialAdmin;
    }

    /// @notice Checks if a user is allowed to execute through the EVVM
    /// @dev Simply returns the boolean value stored in the allowedUsers mapping
    /// @param user The address to check authorization for
    /// @return True if the user has been explicitly allowed by the admin, false otherwise
    function canExecute(address user) external view returns (bool) {
        return allowedUsers[user];
    }

    /// @notice Allows or disallows a user to execute through the EVVM
    /// @dev Can only be called by the admin address (enforced by onlyAdmin modifier)
    /// @param user The address to update authorization for
    /// @param allowed True to allow the user, false to revoke their access
    /// @custom:throws UserNotAllowed If called by an address other than the admin
    function setAllowedUser(address user, bool allowed) external onlyAdmin {
        allowedUsers[user] = allowed;
    }
}