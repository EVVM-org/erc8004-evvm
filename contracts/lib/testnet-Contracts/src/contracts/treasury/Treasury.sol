// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.core.info/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;

import {
    TreasuryError as Error
} from "@evvm/testnet-contracts/library/errors/TreasuryError.sol";

import {ICore as Core} from "@evvm/testnet-contracts/interfaces/ICore.sol";

import {IERC20} from "@evvm/testnet-contracts/library/primitives/IERC20.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

/**
░██████████                                                     
    ░██                                                         
    ░█░██░███░███████░██████ ░███████░██    ░█░██░███░██    ░██ 
    ░█░███  ░██    ░██    ░█░██      ░██    ░█░███   ░██    ░██ 
    ░█░██   ░████████░███████░███████░██    ░█░██    ░██    ░██ 
    ░█░██   ░██     ░██   ░██      ░█░██   ░██░██    ░██   ░███ 
    ░█░██    ░███████░█████░█░███████ ░█████░█░██     ░█████░██ 
                                                            ░██ 
                                                      ░███████  
                                                                
████████╗███████╗███████╗████████╗███╗   ██╗███████╗████████╗
╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝████╗  ██║██╔════╝╚══██╔══╝
   ██║   █████╗  ███████╗   ██║   ██╔██╗ ██║█████╗     ██║   
   ██║   ██╔══╝  ╚════██║   ██║   ██║╚██╗██║██╔══╝     ██║   
   ██║   ███████╗███████║   ██║   ██║ ╚████║███████╗   ██║   
   ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝╚══════╝   ╚═╝   
            
 * @title EVVM Treasury
 * @author Mate labs
 * @notice Vault for depositing and withdrawing assets in the EVVM ecosystem.
 * @dev Handles ETH and ERC20 tokens, syncing balances with Core.sol. 
 *      Principal Tokens are not withdrawable via this contract.
 */

contract Treasury {
    /// @dev Reference to the EVVM core contract for balance management
    Core core;

    /**
     * @notice Initialize Treasury with EVVM contract address
     * @param _coreAddress Address of the EVVM core contract
     */
    constructor(address _coreAddress) {
        core = Core(_coreAddress);
    }

    /**
     * @notice Deposits ETH or ERC20 tokens into EVVM.
     * @dev Credits the user's balance in Core.sol. ETH uses address(0).
     * @param token Token address (address(0) for native ETH).
     * @param amount Amount to deposit (must match msg.value for ETH).
     */
    function deposit(address token, uint256 amount) external payable {
        if (address(0) == token) {
            /// user is sending host native coin
            if (msg.value == 0)
                revert Error.DepositAmountMustBeGreaterThanZero();

            if (amount != msg.value) revert Error.InvalidDepositAmount();
        } else {
            /// user is sending ERC20 tokens

            if (msg.value != 0) revert Error.DepositCoinWithToken();

            if (amount == 0) revert Error.DepositAmountMustBeGreaterThanZero();

            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }

        core.addAmountToUser(msg.sender, token, amount);
    }

    /**
     * @notice Withdraws ETH or ERC20 tokens from EVVM.
     * @dev Deducts from the user's balance in Core.sol. Principal Tokens cannot be withdrawn.
     * @param token Token address to withdraw (address(0) for native ETH).
     * @param amount Amount to withdraw.
     */
    function withdraw(address token, uint256 amount) external {
        if (token == core.getPrincipalTokenAddress())
            revert Error.PrincipalTokenIsNotWithdrawable();

        if (core.getBalance(msg.sender, token) < amount)
            revert Error.InsufficientBalance();

        core.removeAmountFromUser(msg.sender, token, amount);

        if (token == address(0))
            /// user is trying to withdraw native coin
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        else
            /// user is trying to withdraw ERC20 tokens
            IERC20(token).transfer(msg.sender, amount);
    }

    /**
     * @notice Returns the address of the connected EVVM core contract
     * @return Address of the EVVM core contract
     */
    function getCoreAddress() external view returns (address) {
        return address(core);
    }
}
