// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;
/**
 * @title SignatureRecover
 * @author Mate Labs
 * @notice Library for recovering signer addresses from EIP-191 signed messages
 * @dev EIP-191 signer recovery for gasless transaction validation.
 */

import {AdvancedStrings} from "@evvm/testnet-contracts/library/utils/AdvancedStrings.sol";

library SignatureRecover {

    /**
     * @notice Recovers the signer address from an EIP-191 signed message
     * @dev Prepends EIP-191 prefix, hashes with keccak256, then calls ecrecover.
     * @param message Original message (without prefix)
     * @param signature 65-byte signature in the format (r, s, v)
     * @return Signer address, or address(0) if invalid
     */
    function recoverSigner(
        string memory message,
        bytes memory signature
    ) internal pure returns (address) {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                AdvancedStrings.uintToString(bytes(message).length),
                message
            )
        );
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        return ecrecover(messageHash, v, r, s);
    }

    /**
     * @notice Splits a 65-byte signature into its r, s, and v components
     * @dev Extracts components via assembly; normalizes v < 27 by adding 27.
     * @param signature 65-byte signature to split
     * @return r First 32 bytes
     * @return s Second 32 bytes
     * @return v Recovery identifier (27 or 28)
     */
    function splitSignature(
        bytes memory signature
    ) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(signature.length == 65, "Invalid signature length");

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // Ensure signature is valid
        if (v < 27) {
            v += 27;
        }
        require(v == 27 || v == 28, "Invalid signature value");
    }
}
