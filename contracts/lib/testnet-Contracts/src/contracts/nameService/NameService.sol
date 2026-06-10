// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;

import {
    NameServiceError as Error
} from "@evvm/testnet-contracts/library/errors/NameServiceError.sol";
import {
    NameServiceHashUtils as Hash
} from "@evvm/testnet-contracts/library/utils/signature/NameServiceHashUtils.sol";
import {
    NameServiceStructs as Structs
} from "@evvm/testnet-contracts/library/structs/NameServiceStructs.sol";
import {
    IdentityValidation
} from "@evvm/testnet-contracts/contracts/nameService/lib/IdentityValidation.sol";

import {ICore as Core} from "@evvm/testnet-contracts/interfaces/ICore.sol";

import {
    AdvancedStrings
} from "@evvm/testnet-contracts/library/utils/AdvancedStrings.sol";
import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";

/**
 _   _                            
| \ | |                           
|  \| | __ _ _ __ ___   ___       
| . ` |/ _` | '_ ` _ \ / _ \      
| |\  | (_| | | | | | |  __/      
\_| \_/\__,_|_| |_| |_|\___|      
                                  
                                  
 _____                 _          
/  ___|               (_)         
\ `--.  ___ _ ____   ___  ___ ___ 
 `--. \/ _ | '__\ \ / | |/ __/ _ \
/\__/ |  __| |   \ V /| | (_|  __/
\____/ \___|_|    \_/ |_|\___\___|
                                  

████████╗███████╗███████╗████████╗███╗   ██╗███████╗████████╗
╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝████╗  ██║██╔════╝╚══██╔══╝
   ██║   █████╗  ███████╗   ██║   ██╔██╗ ██║█████╗     ██║   
   ██║   ██╔══╝  ╚════██║   ██║   ██║╚██╗██║██╔══╝     ██║   
   ██║   ███████╗███████║   ██║   ██║ ╚████║███████╗   ██║   
   ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝╚══════╝   ╚═╝   
 * @title EVVM Name Service
 * @author Mate labs
 * @notice Identity and username registration system for the EVVM ecosystem.
 * @dev Manages username registration via a commit-reveal scheme (pre-registration), 
 *      a secondary marketplace for domain trading, and customizable user metadata. 
 *      Integrates with Core.sol for payment processing and uses async nonces for high throughput.
 */

contract NameService {
    /// @dev Time delay for accepting proposals (1 day)
    uint256 constant TIME_TO_ACCEPT_PROPOSAL = 1 days;

    /// @dev Principal Tokens locked in pending marketplace
    uint256 private principalTokenTokenLockedForWithdrawOffers;

    /// @dev Nested mapping: username => offer ID => offer
    mapping(string username => mapping(uint256 id => Structs.OfferMetadata))
        private usernameOffers;

    /// @dev Nested mapping: username => key => custom value
    mapping(string username => mapping(uint256 numberKey => string customValue))
        private identityCustomMetadata;

    /// @dev Proposal system for token withdrawal with delay
    ProposalStructs.UintTypeProposal amountToWithdrawTokens;

    /// @dev Proposal system for Core address changes
    ProposalStructs.AddressTypeProposal coreAddress;

    /// @dev Proposal system for admin address changes
    ProposalStructs.AddressTypeProposal admin;

    /// @dev Mapping from username to core metadata
    mapping(string username => Structs.IdentityBaseMetadata basicMetadata)
        private identityDetails;

    /// @dev EVVM contract for payment processing
    Core private core;

    /// @dev Restricts function access to current admin only
    modifier onlyAdmin() {
        if (msg.sender != admin.current) revert Error.SenderIsNotAdmin();

        _;
    }

    //█ Initialization ████████████████████████████████████████████████████████████████████████

    /**
     * @notice Initializes the NameService with the Core contract and initial administrator.
     * @param _coreAddress The address of the EVVM Core contract.
     * @param _initialOwner The address granted administrative privileges.
     */
    constructor(address _coreAddress, address _initialOwner) {
        coreAddress.current = _coreAddress;
        admin.current = _initialOwner;
        core = Core(_coreAddress);
    }

    //█ Registration Functions ████████████████████████████████████████████████████████████████████████

    /**
     * @notice Commits a username hash to prevent front-running before registration.
     * @dev Part of the commit-reveal scheme. Valid for 30 minutes.
     * @param user The address of the registrant.
     * @param hashPreRegisteredUsername The keccak256 hash of (username + secret).
     * @param originExecutor Optional tx.origin restriction.
     * @param nonce Async nonce for signature verification.
     * @param signature Registrant's authorization signature.
     * @param priorityFeePay Optional priority fee for the executor.
     * @param noncePay Nonce for the Core payment (if fee is paid).
     * @param signaturePay Signature for the Core payment (if fee is paid).
     */
    function preRegistrationUsername(
        address user,
        bytes32 hashPreRegisteredUsername,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForPreRegistrationUsername(hashPreRegisteredUsername),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (priorityFeePay > 0)
            requestPay(
                user,
                0,
                priorityFeePay,
                originExecutor,
                noncePay,
                signaturePay
            );

        identityDetails[
            string.concat(
                "@",
                AdvancedStrings.bytes32ToString(hashPreRegisteredUsername)
            )
        ] = Structs.IdentityBaseMetadata({
            owner: user,
            expirationDate: block.timestamp + 30 minutes,
            customMetadataMaxSlots: 0,
            offerMaxSlots: 0,
            flagNotAUsername: 0x01
        });

        if (core.isAddressStaker(msg.sender))
            makeCaPay(msg.sender, core.getRewardAmount() + priorityFeePay);
    }

    /**
     * @notice Finalizes username registration by revealing the secret associated with a pre-registration.
     * @dev Validates format, availability, and payment. Grants 1 year of ownership.
     * @param user The address of the registrant.
     * @param username The plain-text username being registered.
     * @param lockNumber The secret used in the pre-registration hash.
     * @param originExecutor Optional tx.origin restriction.
     * @param nonce Async nonce for signature verification.
     * @param signature Registrant's authorization signature.
     * @param priorityFeePay Optional priority fee for the executor.
     * @param noncePay Nonce for the Core payment (registration fee + priority fee).
     * @param signaturePay Signature for the Core payment.
     */
    function registrationUsername(
        address user,
        string calldata username,
        uint256 lockNumber,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForRegistrationUsername(username, lockNumber),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (
            admin.current != user &&
            !IdentityValidation.isValidUsername(username)
        ) revert Error.InvalidUsername();

        if (!isUsernameAvailable(username))
            revert Error.UsernameAlreadyRegistered();

        requestPay(
            user,
            getPriceOfRegistration(username),
            priorityFeePay,
            originExecutor,
            noncePay,
            signaturePay
        );

        string memory _key = string.concat(
            "@",
            AdvancedStrings.bytes32ToString(hashUsername(username, lockNumber))
        );

        if (
            identityDetails[_key].owner != user ||
            identityDetails[_key].expirationDate > block.timestamp
        ) revert Error.PreRegistrationNotValid();

        identityDetails[username] = Structs.IdentityBaseMetadata({
            owner: user,
            expirationDate: block.timestamp + 366 days,
            customMetadataMaxSlots: 0,
            offerMaxSlots: 0,
            flagNotAUsername: 0x00
        });

        if (core.isAddressStaker(msg.sender))
            makeCaPay(
                msg.sender,
                (50 * core.getRewardAmount()) + priorityFeePay
            );

        delete identityDetails[_key];
    }

    //█ Marketplace Functions ████████████████████████████████████████████████████████████████████████

    /**
     * @notice Places a purchase offer on an existing username.
     * @dev Tokens are locked in the contract. A 0.5% marketplace fee is applied upon successful sale.
     * @param user The address of the offerer.
     * @param username The target username.
     * @param amount Total amount offered (including fee).
     * @param expirationDate When the offer expires.
     * @param originExecutor Optional tx.origin restriction.
     * @param nonce Async nonce for signature verification.
     * @param signature Offerer's authorization signature.
     * @param priorityFeePay Optional priority fee for the executor.
     * @param noncePay Nonce for the Core payment (locks tokens).
     * @param signaturePay Signature for the Core payment.
     * @return offerID The unique ID of the created offer.
     */
    function makeOffer(
        address user,
        string calldata username,
        uint256 amount,
        uint256 expirationDate,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external returns (uint256 offerID) {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForMakeOffer(username, amount, expirationDate),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (
            identityDetails[username].flagNotAUsername == 0x01 ||
            !verifyIfIdentityExists(username)
        ) revert Error.InvalidUsername();

        if (expirationDate <= block.timestamp)
            revert Error.CannotBeBeforeCurrentTime();

        if (amount == 0) revert Error.AmountMustBeGreaterThanZero();

        requestPay(
            user,
            amount,
            priorityFeePay,
            originExecutor,
            noncePay,
            signaturePay
        );

        while (usernameOffers[username][offerID].offerer != address(0))
            offerID++;

        uint256 amountToOffer = ((amount * 995) / 1000);

        usernameOffers[username][offerID] = Structs.OfferMetadata({
            offerer: user,
            expirationDate: expirationDate,
            amount: amountToOffer
        });

        makeCaPay(
            msg.sender,
            core.getRewardAmount() + ((amount * 125) / 100_000) + priorityFeePay
        );

        principalTokenTokenLockedForWithdrawOffers +=
            amountToOffer +
            (amount / 800);

        if (offerID > identityDetails[username].offerMaxSlots) {
            identityDetails[username].offerMaxSlots++;
        } else if (identityDetails[username].offerMaxSlots == 0) {
            identityDetails[username].offerMaxSlots++;
        }
    }

    /**
     * @notice Withdraws a pending marketplace offer and refunds locked tokens to the offerer.
     * @param user Address that made the original offer.
     * @param username Username the offer was made for.
     * @param offerID ID of the offer to withdraw.
     * @param nonce Async nonce for signature verification.
     * @param signature Authorization signature.
     * @param priorityFeePay Optional executor fee.
     * @param noncePay Nonce for the Core payment.
     * @param signaturePay Signature for the Core payment.
     */
    function withdrawOffer(
        address user,
        string calldata username,
        uint256 offerID,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForWithdrawOffer(username, offerID),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (usernameOffers[username][offerID].offerer != user)
            revert Error.UserIsNotOwnerOfOffer();

        if (priorityFeePay > 0)
            requestPay(
                user,
                0,
                priorityFeePay,
                originExecutor,
                noncePay,
                signaturePay
            );

        makeCaPay(user, usernameOffers[username][offerID].amount);

        usernameOffers[username][offerID].offerer = address(0);

        makeCaPay(
            msg.sender,
            core.getRewardAmount() +
                ((usernameOffers[username][offerID].amount * 1) / 796) +
                priorityFeePay
        );

        principalTokenTokenLockedForWithdrawOffers -=
            (usernameOffers[username][offerID].amount) +
            (((usernameOffers[username][offerID].amount * 1) / 199) / 4);
    }

    /**
     * @notice Accepts a marketplace offer, paying the seller and transferring username ownership to the buyer.
     * @param user Address of the current username owner.
     * @param username Username being sold.
     * @param offerID ID of the offer to accept.
     * @param nonce Async nonce for signature verification.
     * @param signature Authorization signature.
     * @param priorityFeePay Optional executor fee.
     * @param noncePay Nonce for the Core payment.
     * @param signaturePay Signature for the Core payment.
     */
    function acceptOffer(
        address user,
        string calldata username,
        uint256 offerID,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForAcceptOffer(username, offerID),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (identityDetails[username].owner != user)
            revert Error.UserIsNotOwnerOfIdentity();

        if (
            usernameOffers[username][offerID].offerer == address(0) ||
            usernameOffers[username][offerID].expirationDate < block.timestamp
        ) revert Error.OfferInactive();

        if (priorityFeePay > 0) {
            requestPay(
                user,
                0,
                priorityFeePay,
                originExecutor,
                noncePay,
                signaturePay
            );
        }

        makeCaPay(user, usernameOffers[username][offerID].amount);

        identityDetails[username].owner = usernameOffers[username][offerID]
            .offerer;

        usernameOffers[username][offerID].offerer = address(0);

        if (core.isAddressStaker(msg.sender)) {
            makeCaPay(
                msg.sender,
                (core.getRewardAmount()) +
                    (((usernameOffers[username][offerID].amount * 1) / 199) /
                        4) +
                    priorityFeePay
            );
        }

        principalTokenTokenLockedForWithdrawOffers -=
            (usernameOffers[username][offerID].amount) +
            (((usernameOffers[username][offerID].amount * 1) / 199) / 4);
    }

    /**
     * @notice Renews username registration by 366 days. Pricing is dynamic based on active offers.
     * @param user Address of the username owner.
     * @param username Username to renew.
     * @param nonce Async nonce for signature verification.
     * @param signature Authorization signature.
     * @param priorityFeePay Optional executor fee.
     * @param noncePay Nonce for the Core payment.
     * @param signaturePay Signature for the Core payment.
     */
    function renewUsername(
        address user,
        string calldata username,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForRenewUsername(username),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (identityDetails[username].owner != user)
            revert Error.UserIsNotOwnerOfIdentity();

        if (identityDetails[username].flagNotAUsername == 0x01)
            revert Error.IdentityIsNotAUsername();

        if (
            identityDetails[username].expirationDate >
            block.timestamp + 36500 days
        ) revert Error.RenewalTimeLimitExceeded();

        uint256 priceOfRenew = seePriceToRenew(username);

        requestPay(
            user,
            priceOfRenew,
            priorityFeePay,
            originExecutor,
            noncePay,
            signaturePay
        );

        if (core.isAddressStaker(msg.sender)) {
            makeCaPay(
                msg.sender,
                core.getRewardAmount() +
                    ((priceOfRenew * 50) / 100) +
                    priorityFeePay
            );
        }

        identityDetails[username].expirationDate += 366 days;
    }

    //█ Metadata Functions ████████████████████████████████████████████████████████████████████████

    /**
     * @notice Adds a custom metadata entry to a username using schema format ([schema]:[subschema]>[value]).
     * @param user Address of the username owner.
     * @param identity Username to add metadata to.
     * @param value Metadata string.
     * @param nonce Async nonce for signature verification.
     * @param signature Authorization signature.
     * @param priorityFeePay Optional executor fee.
     * @param noncePay Nonce for the Core payment.
     * @param signaturePay Signature for the Core payment.
     */
    function addCustomMetadata(
        address user,
        string calldata identity,
        string calldata value,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForAddCustomMetadata(identity, value),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (identityDetails[identity].owner != user)
            revert Error.UserIsNotOwnerOfIdentity();

        if (bytes(value).length == 0) revert Error.EmptyCustomMetadata();

        requestPay(
            user,
            getPriceToAddCustomMetadata(),
            priorityFeePay,
            originExecutor,
            noncePay,
            signaturePay
        );

        if (core.isAddressStaker(msg.sender)) {
            makeCaPay(
                msg.sender,
                (5 * core.getRewardAmount()) +
                    ((getPriceToAddCustomMetadata() * 50) / 100) +
                    priorityFeePay
            );
        }

        identityCustomMetadata[identity][
            identityDetails[identity].customMetadataMaxSlots
        ] = value;

        identityDetails[identity].customMetadataMaxSlots++;
    }

    /**
     * @notice Removes a custom metadata entry by index and shifts subsequent entries to fill the gap.
     * @param user Address of the username owner.
     * @param identity Username to remove metadata from.
     * @param key Index of the metadata entry to remove.
     * @param nonce Async nonce for signature verification.
     * @param signature Authorization signature.
     * @param priorityFeePay Optional executor fee.
     * @param noncePay Nonce for the Core payment.
     * @param signaturePay Signature for the Core payment.
     */
    function removeCustomMetadata(
        address user,
        string calldata identity,
        uint256 key,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForRemoveCustomMetadata(identity, key),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (identityDetails[identity].owner != user)
            revert Error.UserIsNotOwnerOfIdentity();

        if (identityDetails[identity].customMetadataMaxSlots <= key)
            revert Error.InvalidKey();

        requestPay(
            user,
            getPriceToRemoveCustomMetadata(),
            priorityFeePay,
            originExecutor,
            noncePay,
            signaturePay
        );

        if (identityDetails[identity].customMetadataMaxSlots == key) {
            delete identityCustomMetadata[identity][key];
        } else {
            for (
                uint256 i = key;
                i < identityDetails[identity].customMetadataMaxSlots;
                i++
            ) {
                identityCustomMetadata[identity][i] = identityCustomMetadata[
                    identity
                ][i + 1];
            }
            delete identityCustomMetadata[identity][
                identityDetails[identity].customMetadataMaxSlots
            ];
        }

        identityDetails[identity].customMetadataMaxSlots--;

        if (core.isAddressStaker(msg.sender))
            makeCaPay(
                msg.sender,
                (5 * core.getRewardAmount()) + priorityFeePay
            );
    }

    /**
     * @notice Removes all custom metadata entries for a username in a single transaction.
     * @param user Address of the username owner.
     * @param identity Username to clear all metadata from.
     * @param nonce Async nonce for signature verification.
     * @param signature Authorization signature.
     * @param priorityFeePay Optional executor fee.
     * @param noncePay Nonce for the Core payment.
     * @param signaturePay Signature for the Core payment.
     */
    function flushCustomMetadata(
        address user,
        string calldata identity,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForFlushCustomMetadata(identity),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (identityDetails[identity].owner != user)
            revert Error.UserIsNotOwnerOfIdentity();

        if (identityDetails[identity].customMetadataMaxSlots == 0)
            revert Error.EmptyCustomMetadata();

        requestPay(
            user,
            getPriceToFlushCustomMetadata(identity),
            priorityFeePay,
            originExecutor,
            noncePay,
            signaturePay
        );

        for (
            uint256 i = 0;
            i < identityDetails[identity].customMetadataMaxSlots;
            i++
        ) {
            delete identityCustomMetadata[identity][i];
        }

        if (core.isAddressStaker(msg.sender)) {
            makeCaPay(
                msg.sender,
                ((5 * core.getRewardAmount()) *
                    identityDetails[identity].customMetadataMaxSlots) +
                    priorityFeePay
            );
        }

        identityDetails[identity].customMetadataMaxSlots = 0;
    }

    /**
     * @notice Deletes a username and all its metadata, making it available for re-registration.
     * @param user Address of the username owner.
     * @param username Username to delete.
     * @param nonce Async nonce for signature verification.
     * @param signature Authorization signature.
     * @param priorityFeePay Optional executor fee.
     * @param noncePay Nonce for the Core payment.
     * @param signaturePay Signature for the Core payment.
     */
    function flushUsername(
        address user,
        string calldata username,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForFlushUsername(username),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (identityDetails[username].owner != user)
            revert Error.UserIsNotOwnerOfIdentity();

        if (block.timestamp >= identityDetails[username].expirationDate)
            revert Error.OwnershipExpired();

        if (identityDetails[username].flagNotAUsername == 0x01)
            revert Error.IdentityIsNotAUsername();

        requestPay(
            user,
            getPriceToFlushUsername(username),
            priorityFeePay,
            originExecutor,
            noncePay,
            signaturePay
        );

        for (
            uint256 i = 0;
            i < identityDetails[username].customMetadataMaxSlots;
            i++
        ) {
            delete identityCustomMetadata[username][i];
        }

        makeCaPay(
            msg.sender,
            ((5 * core.getRewardAmount()) *
                identityDetails[username].customMetadataMaxSlots) +
                priorityFeePay
        );

        identityDetails[username] = Structs.IdentityBaseMetadata({
            owner: address(0),
            expirationDate: 0,
            customMetadataMaxSlots: 0,
            offerMaxSlots: identityDetails[username].offerMaxSlots,
            flagNotAUsername: 0x00
        });
    }

    //█ Administrative Functions ████████████████████████████████████████████████████████████████████████

    /**
     * @notice Proposes new admin address with 1-day delay
     * @dev Time-delayed governance system for admin changes
     * @param _adminToPropose Address of the proposed new admin
     */
    function proposeAdmin(address _adminToPropose) public onlyAdmin {
        if (_adminToPropose == address(0) || _adminToPropose == admin.current)
            revert Error.InvalidAdminProposal();

        admin.proposal = _adminToPropose;
        admin.timeToAccept = block.timestamp + TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the current admin proposal
     * @dev Only the current admin can cancel pending proposals
     */
    function cancelProposeAdmin() public onlyAdmin {
        admin.proposal = address(0);
        admin.timeToAccept = 0;
    }

    /**
     * @notice Accepts the admin proposal and becomes the new admin
     * @dev Can only be called by the proposed admin after the time delay has passed
     */
    function acceptProposeAdmin() public {
        if (admin.proposal != msg.sender)
            revert Error.SenderIsNotProposedAdmin();

        if (block.timestamp < admin.timeToAccept)
            revert Error.LockTimeNotExpired();

        admin = ProposalStructs.AddressTypeProposal({
            current: admin.proposal,
            proposal: address(0),
            timeToAccept: 0
        });
    }

    /**
     * @notice Proposes to withdraw Principal Tokens from the contract
     * @dev Amount must be available after reserving funds for operations and locked offers
     * @param _amount Amount of Principal Tokens to withdraw
     */
    function proposeWithdrawPrincipalTokens(uint256 _amount) public onlyAdmin {
        if (
            core.getBalance(address(this), core.getPrincipalTokenAddress()) -
                (5083 +
                    core.getRewardAmount() +
                    principalTokenTokenLockedForWithdrawOffers) <
            _amount ||
            _amount == 0
        ) {
            revert Error.InvalidWithdrawAmount();
        }

        amountToWithdrawTokens.proposal = _amount;
        amountToWithdrawTokens.timeToAccept =
            block.timestamp +
            TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the pending token withdrawal proposal
     * @dev Only the current admin can cancel pending proposals
     */
    function cancelWithdrawPrincipalTokens() public onlyAdmin {
        amountToWithdrawTokens.proposal = 0;
        amountToWithdrawTokens.timeToAccept = 0;
    }

    /**
     * @notice Executes the approved token withdrawal
     * @dev Can only be called after the time delay has passed
     */
    function claimWithdrawPrincipalTokens() public onlyAdmin {
        if (block.timestamp < amountToWithdrawTokens.timeToAccept)
            revert Error.LockTimeNotExpired();

        makeCaPay(admin.current, amountToWithdrawTokens.proposal);

        amountToWithdrawTokens.proposal = 0;
        amountToWithdrawTokens.timeToAccept = 0;
    }

    /**
     * @notice Proposes to change the EVVM contract address
     * @dev Critical function that affects payment processing integration
     * @param _newEvvmAddress Address of the new EVVM contract
     */
    function proposeChangeEvvmAddress(
        address _newEvvmAddress
    ) public onlyAdmin {
        if (_newEvvmAddress == address(0)) revert Error.InvalidEvvmAddress();

        coreAddress.proposal = _newEvvmAddress;
        coreAddress.timeToAccept = block.timestamp + TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the pending EVVM address change proposal
     * @dev Only the current admin can cancel pending proposals
     */
    function cancelChangeEvvmAddress() public onlyAdmin {
        coreAddress.proposal = address(0);
        coreAddress.timeToAccept = 0;
    }

    /**
     * @notice Executes the approved EVVM address change
     * @dev Can only be called after the time delay has passed
     */
    function acceptChangeEvvmAddress() public onlyAdmin {
        if (block.timestamp < coreAddress.timeToAccept)
            revert Error.LockTimeNotExpired();

        coreAddress = ProposalStructs.AddressTypeProposal({
            current: coreAddress.proposal,
            proposal: address(0),
            timeToAccept: 0
        });

        core = Core(coreAddress.current);
    }

    //█ Utility Functions ████████████████████████████████████████████████████████████████████████

    //█ EVVM Payment Integration ██████████████████████████████████████████████

    /**
     * @notice Routes a Principal Token payment through Core. Always uses async nonce (isAsyncExec = true).
     * @param user Payer address.
     * @param amount Amount in Principal Tokens.
     * @param priorityFee Optional executor fee.
     * @param nonce Async nonce for the Core payment.
     * @param signature Authorization signature.
     */
    function requestPay(
        address user,
        uint256 amount,
        uint256 priorityFee,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature
    ) internal {
        core.pay(
            user,
            address(this),
            "",
            core.getPrincipalTokenAddress(),
            amount,
            priorityFee,
            address(this),
            originExecutor,
            nonce,
            true,
            signature
        );
    }

    /**
     * @notice Transfers Principal Tokens to a user via Core.caPay.
     * @param user Recipient address.
     * @param amount Amount to send.
     */
    function makeCaPay(address user, uint256 amount) internal {
        core.caPay(user, core.getPrincipalTokenAddress(), amount);
    }

    //█ Username Hashing Functions ███████████████████████████████████████████████████████████████████

    /**
     * @notice Returns keccak256(username, randomNumber) for use in the commit-reveal pre-registration scheme.
     */
    function hashUsername(
        string calldata _username,
        uint256 _randomNumber
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_username, _randomNumber));
    }

    //█ View Functions - Public Data Access ██████████████████████████████████████████████████████████

    //█ Service Functions ████████████████████████████████████████████████████████████████

    /**
     * @notice Checks if an identity exists in the system
     * @dev Handles both pre-registrations and actual username registrations
     * @param _identity The identity/username to check
     * @return True if the identity exists and is valid
     */
    function verifyIfIdentityExists(
        string calldata _identity
    ) public view returns (bool) {
        if (identityDetails[_identity].flagNotAUsername == 0x01) {
            if (
                identityDetails[_identity].owner == address(0) ||
                identityDetails[_identity].expirationDate != 0
            ) {
                return false;
            } else {
                return true;
            }
        } else {
            if (identityDetails[_identity].expirationDate == 0) {
                return false;
            } else {
                return true;
            }
        }
    }

    /**
     * @notice Strictly verifies if an identity exists and reverts if not found
     * @dev More strict version that reverts instead of returning false
     * @param _username The username to verify
     * @return True if the username exists (will revert if not)
     */
    function strictVerifyIfIdentityExist(
        string calldata _username
    ) public view returns (bool) {
        if (identityDetails[_username].flagNotAUsername == 0x01) {
            if (
                identityDetails[_username].owner == address(0) ||
                identityDetails[_username].expirationDate != 0
            ) {
                revert();
            } else {
                return true;
            }
        } else {
            if (identityDetails[_username].expirationDate == 0) {
                revert();
            } else {
                return true;
            }
        }
    }

    /**
     * @notice Returns the owner address of a registered identity.
     */
    function getOwnerOfIdentity(
        string calldata _username
    ) public view returns (address) {
        return identityDetails[_username].owner;
    }

    /**
     * @notice Reverts if the identity does not exist; returns the owner address if it does.
     */
    function verifyStrictAndGetOwnerOfIdentity(
        string calldata _username
    ) public view returns (address answer) {
        if (strictVerifyIfIdentityExist(_username))
            answer = identityDetails[_username].owner;
    }

    /**
     * @notice Calculates the cost to renew a username registration
     * @dev Pricing varies based on timing and market demand:
     *      - Free if renewed before expiration (within grace period)
     *      - Variable cost based on highest active offer (minimum 500 Principal Token)
     *      - Fixed 500,000 Principal Token if renewed more than 1 year before expiration
     * @param _identity The username to calculate renewal price for
     * @return price The cost in Principal Tokens to renew the username
     */
    function seePriceToRenew(
        string calldata _identity
    ) public view returns (uint256 price) {
        if (identityDetails[_identity].expirationDate >= block.timestamp) {
            if (usernameOffers[_identity][0].expirationDate != 0) {
                for (
                    uint256 i = 0;
                    i < identityDetails[_identity].offerMaxSlots;
                    i++
                ) {
                    if (
                        usernameOffers[_identity][i].expirationDate >
                        block.timestamp &&
                        usernameOffers[_identity][i].offerer != address(0)
                    ) {
                        if (usernameOffers[_identity][i].amount > price) {
                            price = usernameOffers[_identity][i].amount;
                        }
                    }
                }
            }
            if (price == 0) {
                price = 500 * 10 ** 18;
            } else {
                uint256 principalTokenReward = core.getRewardAmount();

                price = ((price * 5) / 1000) > (500000 * principalTokenReward)
                    ? (500000 * principalTokenReward)
                    : ((price * 5) / 1000);
            }
        } else {
            price = 500_000 * core.getRewardAmount();
        }
    }

    /**
     * @notice Gets the current price to add custom metadata to a username
     * @dev Price is dynamic based on current EVVM reward amount
     * @return price Cost in Principal Tokens (10x current reward amount)
     */
    function getPriceToAddCustomMetadata() public view returns (uint256 price) {
        price = 10 * core.getRewardAmount();
    }

    /**
     * @notice Gets the current price to remove a single custom metadata entry
     * @dev Price is dynamic based on current EVVM reward amount
     * @return price Cost in Principal Tokens (10x current reward amount)
     */
    function getPriceToRemoveCustomMetadata()
        public
        view
        returns (uint256 price)
    {
        price = 10 * core.getRewardAmount();
    }

    /**
     * @notice Gets the cost to remove all custom metadata entries from a username
     * @dev Cost scales with the number of metadata entries to remove
     * @param _identity The username to calculate flush cost for
     * @return price Total cost in Principal Tokens (10x reward amount per metadata entry)
     */
    function getPriceToFlushCustomMetadata(
        string calldata _identity
    ) public view returns (uint256 price) {
        price =
            (10 * core.getRewardAmount()) *
            identityDetails[_identity].customMetadataMaxSlots;
    }

    /**
     * @notice Gets the cost to completely remove a username and all its data
     * @dev Includes cost for metadata removal plus base username deletion fee
     * @param _identity The username to calculate deletion cost for
     * @return price Total cost in Principal Tokens (metadata flush cost + 1x reward amount)
     */
    function getPriceToFlushUsername(
        string calldata _identity
    ) public view returns (uint256 price) {
        price =
            ((10 * core.getRewardAmount()) *
                identityDetails[_identity].customMetadataMaxSlots) +
            core.getRewardAmount();
    }

    //█ Identity Availability Functions ██████████████████████████████████████████████████████████████

    /**
     * @notice Checks if a username is available for registration
     * @dev A username is available if it was never registered or has been expired for 60+ days
     * @param _username The username to check availability for
     * @return True if the username is available for registration
     */
    function isUsernameAvailable(
        string calldata _username
    ) public view returns (bool) {
        if (identityDetails[_username].expirationDate == 0) {
            return true;
        } else {
            return
                identityDetails[_username].expirationDate + 60 days <
                block.timestamp;
        }
    }

    /**
     * @notice Returns the owner address and expiration timestamp of a username.
     */
    function getIdentityBasicMetadata(
        string calldata _username
    ) public view returns (address, uint256) {
        return (
            identityDetails[_username].owner,
            identityDetails[_username].expirationDate
        );
    }

    /**
     * @notice Returns the number of custom metadata entries for a username.
     */
    function getAmountOfCustomMetadata(
        string calldata _username
    ) public view returns (uint256) {
        return identityDetails[_username].customMetadataMaxSlots;
    }

    /**
     * @notice Returns all custom metadata entries for a username as an ordered array.
     */
    function getFullCustomMetadataOfIdentity(
        string calldata _username
    ) public view returns (string[] memory) {
        string[] memory _customMetadata = new string[](
            identityDetails[_username].customMetadataMaxSlots
        );
        for (
            uint256 i = 0;
            i < identityDetails[_username].customMetadataMaxSlots;
            i++
        ) {
            _customMetadata[i] = identityCustomMetadata[_username][i];
        }
        return _customMetadata;
    }

    /**
     * @notice Returns the custom metadata entry at a specific index for a username.
     */
    function getSingleCustomMetadataOfIdentity(
        string calldata _username,
        uint256 _key
    ) public view returns (string memory) {
        return identityCustomMetadata[_username][_key];
    }

    /**
     * @notice Returns the total number of metadata slots for a username.
     */
    function getCustomMetadataMaxSlotsOfIdentity(
        string calldata _username
    ) public view returns (uint256) {
        return identityDetails[_username].customMetadataMaxSlots;
    }

    //█ Username Marketplace Functions ███████████████████████████████████████████████████████████████

    /**
     * @notice Gets all offers made for a specific username
     * @dev Returns both active and expired offers that haven't been withdrawn
     * @param _username The username to get offers for
     * @return offers Array of all offer metadata structures
     */
    function getOffersOfUsername(
        string calldata _username
    ) public view returns (Structs.OfferMetadata[] memory offers) {
        offers = new Structs.OfferMetadata[](
            identityDetails[_username].offerMaxSlots
        );

        for (uint256 i = 0; i < identityDetails[_username].offerMaxSlots; i++) {
            offers[i] = usernameOffers[_username][i];
        }
    }

    /**
     * @notice Returns the offer metadata for a specific username and offer ID.
     */
    function getSingleOfferOfUsername(
        string calldata _username,
        uint256 _offerID
    ) public view returns (Structs.OfferMetadata memory offer) {
        return usernameOffers[_username][_offerID];
    }

    /**
     * @notice Counts the total number of offers made for a username
     * @dev Iterates through offers to find the actual count of non-empty slots
     * @param _username The username to count offers for
     * @return length Total number of offers that have been made
     */
    function getLengthOfOffersUsername(
        string calldata _username
    ) public view returns (uint256 length) {
        do {
            length++;
        } while (usernameOffers[_username][length].expirationDate != 0);
    }

    /**
     * @notice Returns the expiration timestamp of a username registration.
     */
    function getExpireDateOfIdentity(
        string calldata _identity
    ) public view returns (uint256) {
        return identityDetails[_identity].expirationDate;
    }

    /**
     * @notice Gets price to register an username
     * @dev Price is fully dynamic based on existing offers and timing
     *      - If dosnt have offers, price is 100x current EVVM reward amount
     *      - If has offers, price is calculated via seePriceToRenew function
     * @param username The username to get registration price for
     * @return The current registration price in Principal Tokens
     */
    function getPriceOfRegistration(
        string calldata username
    ) public view returns (uint256) {
        return
            identityDetails[username].offerMaxSlots > 0
                ? seePriceToRenew(username)
                : core.getRewardAmount() * 100;
    }

    //█ Administrative Getters ███████████████████████████████████████████████████████████████████████

    /**
     * @notice Returns the current admin address.
     */
    function getAdmin() public view returns (address) {
        return admin.current;
    }

    /**
     * @notice Returns admin proposal details: current address, proposed address, and acceptance timestamp.
     */
    function getAdminFullDetails()
        public
        view
        returns (
            address currentAdmin,
            address proposalAdmin,
            uint256 timeToAcceptAdmin
        )
    {
        return (admin.current, admin.proposal, admin.timeToAccept);
    }

    /**
     * @notice Returns the pending token withdrawal proposal amount and acceptance timestamp.
     */
    function getProposedWithdrawAmountFullDetails()
        public
        view
        returns (
            uint256 proposalAmountToWithdrawTokens,
            uint256 timeToAcceptAmountToWithdrawTokens
        )
    {
        return (
            amountToWithdrawTokens.proposal,
            amountToWithdrawTokens.timeToAccept
        );
    }

    /**
     * @notice Returns the EvvmID of the integrated Core instance.
     */
    function getEvvmID() external view returns (uint256) {
        return core.getEvvmID();
    }

    /**
     * @notice Returns the current Core contract address.
     */
    function getCoreAddress() public view returns (address) {
        return coreAddress.current;
    }

    /**
     * @notice Returns Core address proposal details: current address, proposed address, and acceptance timestamp.
     */
    function getCoreAddressFullDetails()
        public
        view
        returns (
            address currentEvvmAddress,
            address proposalEvvmAddress,
            uint256 timeToAcceptEvvmAddress
        )
    {
        return (
            coreAddress.current,
            coreAddress.proposal,
            coreAddress.timeToAccept
        );
    }
}
