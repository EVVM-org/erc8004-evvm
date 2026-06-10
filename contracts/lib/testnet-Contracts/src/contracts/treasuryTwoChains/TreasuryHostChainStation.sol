// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;

import {
    CrossChainTreasuryError as Error
} from "@evvm/testnet-contracts/library/errors/CrossChainTreasuryError.sol";
import {
    TreasuryCrossChainHashUtils as Hash
} from "@evvm/testnet-contracts/library/utils/signature/TreasuryCrossChainHashUtils.sol";
import {
    HostChainStationStructs as Structs
} from "@evvm/testnet-contracts/library/structs/HostChainStationStructs.sol";
import {
    PayloadUtils
} from "@evvm/testnet-contracts/contracts/treasuryTwoChains/lib/PayloadUtils.sol";

import {ICore as Core} from "@evvm/testnet-contracts/interfaces/ICore.sol";

import {
    AdvancedStrings
} from "@evvm/testnet-contracts/library/utils/AdvancedStrings.sol";
import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMailbox} from "@hyperlane-xyz/core/contracts/interfaces/IMailbox.sol";
import {
    MessagingParams,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {
    OApp,
    Origin,
    MessagingFee
} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {
    OAppOptionsType3
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import {
    OptionsBuilder
} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {
    AxelarExecutable
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {
    IAxelarGasService
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import {
    IInterchainGasEstimation
} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IInterchainGasEstimation.sol";


/**
 _____                                                       
/__   \_ __ ___  __ _ ___ _   _ _ __ _   _                   
  / /\| '__/ _ \/ _` / __| | | | '__| | | |                  
 / /  | | |  __| (_| \__ | |_| | |  | |_| |                  
 \/   |_|  \___|\__,_|___/\__,_|_|   \__, |                  
                                     |___/                   
   ___ _           _       __ _        _   _                 
  / __| |__   __ _(_)_ __ / _| |_ __ _| |_(_) ___  _ __      
 / /  | '_ \ / _` | | '_ \\ \| __/ _` | __| |/ _ \| '_ \     
/ /___| | | | (_| | | | | _\ | || (_| | |_| | (_) | | | |    
\____/|_| |_|\__,_|_|_| |_\__/\__\__,_|\__|_|\___/|_| |_|    
                                                             
                                                             
                                                             
 _____ _____ _____ _____ _____ _____ _____ _____ _____ _____ 
|_____|_____|_____|_____|_____|_____|_____|_____|_____|_____|
                                                             
    __  __           __          __          _     
   / / / ____  _____/ /_   _____/ /_  ____ _(_____ 
  / /_/ / __ \/ ___/ __/  / ___/ __ \/ __ `/ / __ \
 / __  / /_/ (__  / /_   / /__/ / / / /_/ / / / / /
/_/ /_/\____/____/\__/   \___/_/ /_/\__,_/_/_/ /_/ 
                                                   
 * @title EVVM Host Chain Station
 * @author Mate labs
 * @notice Manages cross-chain withdrawals from the EVVM host chain to an external chain.
 * @dev Multi-protocol bridge supporting Hyperlane, LayerZero V2, and Axelar. 
 *      Integrates with Core.sol for balance updates and uses Fisher-specific nonces.
 */

contract TreasuryHostChainStation is OApp, OAppOptionsType3, AxelarExecutable {
    /// @notice EVVM core contract for balance operations
    Core core;

    /// @notice Admin address management with time-delayed proposals
    /// @dev Stores current admin, proposed admin, and acceptance timestamp
    ProposalStructs.AddressTypeProposal admin;

    /// @notice Fisher executor address management with time-delayed proposals
    ProposalStructs.AddressTypeProposal fisherExecutor;

    /// @notice Hyperlane protocol configuration for cross-chain messaging
    /// @dev Contains domain ID, external chain address, and mailbox contract address
    Structs.HyperlaneConfig hyperlane;

    /// @notice LayerZero protocol configuration for omnichain messaging
    /// @dev Contains endpoint ID, external chain address, and endpoint contract address
    Structs.LayerZeroConfig layerZero;

    /// @notice Axelar protocol configuration for cross-chain communication
    /// @dev Contains chain name, external chain address, gas service, and gateway addresses
    Structs.AxelarConfig axelar;

    /// @notice Pending proposal for changing external chain addresses across all protocols
    /// @dev Used for coordinated updates to external chain addresses with time delay
    Structs.ChangeExternalChainAddressParams externalChainAddressChangeProposal;

    /// @notice LayerZero execution options with gas limit configuration
    /// @dev Pre-built options for LayerZero message execution (200k gas limit)
    bytes options =
        OptionsBuilder.addExecutorLzReceiveOption(
            OptionsBuilder.newOptions(),
            200_000,
            0
        );

    /// @notice One-time fuse for setting initial external chain addresses
    bytes1 fuseSetExternalChainAddress = 0x01;

    /// @notice Emitted when Fisher bridge sends tokens from host to external chain
    /// @param from Original sender address on host chain
    /// @param addressToReceive Recipient address on external chain
    /// @param tokenAddress Token contract address (address(0) for ETH)
    /// @param priorityFee Fee paid for priority processing
    /// @param amount Amount of tokens transferred
    /// @param nonce Sequential nonce for the Fisher bridge operation
    event FisherBridgeSend(
        address indexed from,
        address indexed addressToReceive,
        address indexed tokenAddress,
        uint256 priorityFee,
        uint256 amount,
        uint256 nonce
    );

    /// @notice Restricts function access to the current admin only
    modifier onlyAdmin() {
        if (msg.sender != admin.current) {
            revert();
        }
        _;
    }

    /// @notice Restricts function access to the current Fisher executor only
    modifier onlyFisherExecutor() {
        if (msg.sender != fisherExecutor.current) {
            revert();
        }
        _;
    }

    /// @notice Initializes the Host Chain Station with EVVM integration and cross-chain protocols
    /// @dev Sets up Hyperlane, LayerZero, and Axelar configurations for multi-protocol support
    /// @param _coreAddress Address of the EVVM core contract for balance operations
    /// @param _admin Initial admin address with full administrative privileges
    /// @param _crosschainConfig Configuration struct containing all cross-chain protocol settings
    constructor(
        address _coreAddress,
        address _admin,
        Structs.CrosschainConfig memory _crosschainConfig
    )
        OApp(_crosschainConfig.layerZero.endpointAddress, _admin)
        Ownable(_admin)
        AxelarExecutable(_crosschainConfig.axelar.gatewayAddress)
    {
        core = Core(_coreAddress);

        admin = ProposalStructs.AddressTypeProposal({
            current: _admin,
            proposal: address(0),
            timeToAccept: 0
        });
        hyperlane = Structs.HyperlaneConfig({
            externalChainStationDomainId: _crosschainConfig
                .hyperlane
                .externalChainStationDomainId,
            externalChainStationAddress: "",
            mailboxAddress: _crosschainConfig.hyperlane.mailboxAddress
        });
        layerZero = Structs.LayerZeroConfig({
            externalChainStationEid: _crosschainConfig
                .layerZero
                .externalChainStationEid,
            externalChainStationAddress: "",
            endpointAddress: _crosschainConfig.layerZero.endpointAddress
        });
        axelar = Structs.AxelarConfig({
            externalChainStationChainName: _crosschainConfig
                .axelar
                .externalChainStationChainName,
            externalChainStationAddress: "",
            gasServiceAddress: _crosschainConfig.axelar.gasServiceAddress,
            gatewayAddress: _crosschainConfig.axelar.gatewayAddress
        });
    }

    /// @notice One-time setup of external chain station address across all protocols
    /// @dev Can only be called once (protected by fuseSetExternalChainAddress)
    /// @param externalChainStationAddress Address-type representation for Hyperlane and LayerZero
    /// @param externalChainStationAddressString String representation for Axelar protocol
    function _setExternalChainAddress(
        address externalChainStationAddress,
        string calldata externalChainStationAddressString
    ) external onlyAdmin {
        if (fuseSetExternalChainAddress != 0x01) revert();

        hyperlane.externalChainStationAddress = bytes32(
            uint256(uint160(externalChainStationAddress))
        );
        layerZero.externalChainStationAddress = bytes32(
            uint256(uint160(externalChainStationAddress))
        );
        axelar.externalChainStationAddress = externalChainStationAddressString;
        _setPeer(
            layerZero.externalChainStationEid,
            layerZero.externalChainStationAddress
        );

        fuseSetExternalChainAddress = 0x00;
    }

    /**
     * @notice Withdraws tokens from EVVM and bridges to the external chain via the selected protocol.
     * @dev Deducts the sender's Core balance before dispatching the cross-chain message.
     * @param toAddress Recipient on external chain
     * @param token Token address (not the principal token)
     * @param amount Amount to withdraw
     * @param protocolToExecute 0x01=Hyperlane, 0x02=LayerZero, 0x03=Axelar
     */
    function withdraw(
        address toAddress,
        address token,
        uint256 amount,
        bytes1 protocolToExecute
    ) external payable {
        if (token == core.getEvvmMetadata().principalTokenAddress)
            revert Error.PrincipalTokenIsNotWithdrawable();

        if (core.getBalance(msg.sender, token) < amount)
            revert Error.InsufficientBalance();

        executerCore(false, msg.sender, token, amount);

        bytes memory payload = PayloadUtils.encodePayload(
            token,
            toAddress,
            amount
        );

        if (protocolToExecute == 0x01) {
            // 0x01 = Hyperlane
            uint256 quote = getQuoteHyperlane(toAddress, token, amount);
            /*messageId = */ IMailbox(hyperlane.mailboxAddress).dispatch{
                value: quote
            }(
                hyperlane.externalChainStationDomainId,
                hyperlane.externalChainStationAddress,
                payload
            );
        } else if (protocolToExecute == 0x02) {
            // 0x02 = LayerZero
            _lzSend(
                layerZero.externalChainStationEid,
                payload,
                options,
                MessagingFee(msg.value, 0),
                msg.sender // Refund any excess fees to the sender.
            );
        } else if (protocolToExecute == 0x03) {
            // 0x03 = Axelar
            IAxelarGasService(axelar.gasServiceAddress)
                .payNativeGasForContractCall{value: msg.value}(
                address(this),
                axelar.externalChainStationChainName,
                axelar.externalChainStationAddress,
                payload,
                msg.sender
            );
            gateway().callContract(
                axelar.externalChainStationChainName,
                axelar.externalChainStationAddress,
                payload
            );
        } else {
            revert();
        }
    }

    /**
     * @notice Credits Core balances for a Fisher bridge deposit originating from the external chain.
     * @dev Validates ECDSA signature via Core.validateAndConsumeNonce and credits recipient plus executor fee.
     * @param from Original sender on external chain
     * @param addressToReceive Recipient on host chain
     * @param tokenAddress Token address (address(0) for ETH)
     * @param priorityFee Fee for Fisher executor
     * @param amount Token amount to credit
     * @param nonce Async nonce from user
     * @param signature ECDSA signature from `from`
     */
    function fisherBridgeReceive(
        address from,
        address addressToReceive,
        address tokenAddress,
        uint256 priorityFee,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external onlyFisherExecutor {
        core.validateAndConsumeNonce(
            from,
            fisherExecutor.current,
            Hash.hashDataForFisherBridge(
                addressToReceive,
                tokenAddress,
                priorityFee,
                amount
            ),
            fisherExecutor.current,
            nonce,
            true,
            signature
        );

        executerCore(true, addressToReceive, tokenAddress, amount);

        if (priorityFee > 0)
            executerCore(true, msg.sender, tokenAddress, priorityFee);
    }

    /**
     * @notice Deducts Core balance and emits a Fisher bridge withdrawal event for the external chain.
     * @dev Validates ECDSA signature, removes amount+fee from sender, credits executor fee, emits FisherBridgeSend.
     * @param from Sender (signer) on host chain
     * @param addressToReceive Recipient on external chain
     * @param tokenAddress Token address (not the principal token)
     * @param priorityFee Fee for Fisher executor
     * @param amount Amount to bridge
     * @param nonce Async nonce from user
     * @param signature ECDSA signature from `from`
     */
    function fisherBridgeSend(
        address from,
        address addressToReceive,
        address tokenAddress,
        uint256 priorityFee,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external onlyFisherExecutor {
        if (tokenAddress == core.getEvvmMetadata().principalTokenAddress)
            revert Error.PrincipalTokenIsNotWithdrawable();

        if (core.getBalance(from, tokenAddress) < amount)
            revert Error.InsufficientBalance();

        core.validateAndConsumeNonce(
            from,
            fisherExecutor.current,
            Hash.hashDataForFisherBridge(
                addressToReceive,
                tokenAddress,
                priorityFee,
                amount
            ),
            fisherExecutor.current,
            nonce,
            true,
            signature
        );

        executerCore(false, from, tokenAddress, amount + priorityFee);

        if (priorityFee > 0)
            executerCore(true, msg.sender, tokenAddress, priorityFee);

        emit FisherBridgeSend(
            from,
            addressToReceive,
            tokenAddress,
            priorityFee,
            amount,
            nonce
        );
    }

    // Hyperlane Specific Functions //

    /// @notice Calculates the fee required for Hyperlane cross-chain message dispatch
    /// @dev Queries the Hyperlane mailbox for accurate fee estimation
    /// @param toAddress Recipient address on the destination chain
    /// @param token Token contract address being transferred
    /// @param amount Amount of tokens being transferred
    /// @return Fee amount in native currency required for the Hyperlane message
    function getQuoteHyperlane(
        address toAddress,
        address token,
        uint256 amount
    ) public view returns (uint256) {
        return
            IMailbox(hyperlane.mailboxAddress).quoteDispatch(
                hyperlane.externalChainStationDomainId,
                hyperlane.externalChainStationAddress,
                PayloadUtils.encodePayload(token, toAddress, amount)
            );
    }

    /**
     * @notice Handles incoming Hyperlane messages from the external chain and credits EVVM balances.
     * @dev Validates mailbox caller, origin domain, and sender address before calling decodeAndDeposit.
     * @param _origin Source chain domain ID
     * @param _sender Sender address (external station)
     * @param _data Encoded payload (token, to, amount)
     */
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _data
    ) external payable virtual {
        if (msg.sender != hyperlane.mailboxAddress)
            revert Error.MailboxNotAuthorized();

        if (_sender != hyperlane.externalChainStationAddress)
            revert Error.SenderNotAuthorized();

        if (_origin != hyperlane.externalChainStationDomainId)
            revert Error.ChainIdNotAuthorized();

        decodeAndDeposit(_data);
    }

    // LayerZero Specific Functions //

    /// @notice Calculates the fee required for LayerZero cross-chain message
    /// @dev Queries LayerZero endpoint for accurate native fee estimation
    /// @param toAddress Recipient address on the destination chain
    /// @param token Token contract address being transferred
    /// @param amount Amount of tokens being transferred
    /// @return Native fee amount required for the LayerZero message
    function quoteLayerZero(
        address toAddress,
        address token,
        uint256 amount
    ) public view returns (uint256) {
        MessagingFee memory fee = _quote(
            layerZero.externalChainStationEid,
            PayloadUtils.encodePayload(token, toAddress, amount),
            options,
            false
        );
        return fee.nativeFee;
    }

    /**
     * @notice Handles incoming LayerZero messages from the external chain and credits EVVM balances.
     * @dev Validates source EID and sender address before calling decodeAndDeposit.
     * @param _origin Origin info (srcEid, sender, nonce)
     * @param message Encoded payload (token, to, amount)
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32 /*_guid*/,
        bytes calldata message,
        address /*executor*/, // Executor address as specified by the OApp.
        bytes calldata /*_extraData*/ // Any extra data or options to trigger on receipt.
    ) internal override {
        // Decode the payload to get the message
        if (_origin.srcEid != layerZero.externalChainStationEid)
            revert Error.ChainIdNotAuthorized();

        if (_origin.sender != layerZero.externalChainStationAddress)
            revert Error.SenderNotAuthorized();

        decodeAndDeposit(message);
    }

    /// @notice Sends LayerZero messages to the destination chain
    /// @dev Handles fee payment and message dispatch through LayerZero endpoint
    /// @param _dstEid Destination endpoint ID (target chain)
    /// @param _message Encoded message payload to send
    /// @param _options Execution options for the destination chain
    /// @param _fee Messaging fee structure (native + LZ token fees)
    /// @param _refundAddress Address to receive excess fees
    /// @return receipt Messaging receipt with transaction details
    function _lzSend(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        MessagingFee memory _fee,
        address _refundAddress
    ) internal override returns (MessagingReceipt memory receipt) {
        // @dev Push corresponding fees to the endpoint, any excess is sent back to the _refundAddress from the endpoint.
        uint256 messageValue = _fee.nativeFee;
        if (_fee.lzTokenFee > 0) _payLzToken(_fee.lzTokenFee);

        return
            // solhint-disable-next-line check-send-result
            endpoint.send{value: messageValue}(
                MessagingParams(
                    _dstEid,
                    _getPeerOrRevert(_dstEid),
                    _message,
                    _options,
                    _fee.lzTokenFee > 0
                ),
                _refundAddress
            );
    }

    // Axelar Specific Functions //

    /**
     * @notice Handles incoming Axelar messages from the external chain and credits EVVM balances.
     * @dev Validates source chain name and address before calling decodeAndDeposit.
     * @param _sourceChain Source blockchain name
     * @param _sourceAddress Source contract address
     * @param _payload Encoded payload (token, to, amount)
     */
    function _execute(
        bytes32 /*commandId*/,
        string calldata _sourceChain,
        string calldata _sourceAddress,
        bytes calldata _payload
    ) internal override {
        if (
            !AdvancedStrings.equal(
                _sourceChain,
                axelar.externalChainStationChainName
            )
        ) revert Error.ChainIdNotAuthorized();

        if (
            !AdvancedStrings.equal(
                _sourceAddress,
                axelar.externalChainStationAddress
            )
        ) revert Error.SenderNotAuthorized();

        decodeAndDeposit(_payload);
    }

    /// @notice Proposes a new admin address with 1-day time delay
    /// @param _newOwner Address of the proposed new admin (cannot be zero or current admin)
    function proposeAdmin(address _newOwner) external onlyAdmin {
        if (_newOwner == address(0) || _newOwner == admin.current) revert();

        admin.proposal = _newOwner;
        admin.timeToAccept = block.timestamp + 1 minutes;
    }

    /// @notice Cancels a pending admin change proposal
    function rejectProposalAdmin() external onlyAdmin {
        admin.proposal = address(0);
        admin.timeToAccept = 0;
    }

    /// @notice Accepts a pending admin proposal and becomes the new admin
    function acceptAdmin() external {
        if (block.timestamp < admin.timeToAccept) revert();

        if (msg.sender != admin.proposal) revert();

        admin.current = admin.proposal;

        admin.proposal = address(0);
        admin.timeToAccept = 0;

        _transferOwnership(admin.current);
    }

    /// @notice Proposes a new Fisher executor address with 1-day time delay
    /// @param _newFisherExecutor Address of the proposed new Fisher executor
    function proposeFisherExecutor(
        address _newFisherExecutor
    ) external onlyAdmin {
        if (
            _newFisherExecutor == address(0) ||
            _newFisherExecutor == fisherExecutor.current
        ) revert();

        fisherExecutor.proposal = _newFisherExecutor;
        fisherExecutor.timeToAccept = block.timestamp + 1 minutes;
    }

    /// @notice Cancels a pending Fisher executor change proposal
    function rejectProposalFisherExecutor() external onlyAdmin {
        fisherExecutor.proposal = address(0);
        fisherExecutor.timeToAccept = 0;
    }

    /// @notice Accepts a pending Fisher executor proposal
    function acceptFisherExecutor() external {
        if (block.timestamp < fisherExecutor.timeToAccept) revert();

        if (msg.sender != fisherExecutor.proposal) revert();

        fisherExecutor.current = fisherExecutor.proposal;

        fisherExecutor.proposal = address(0);
        fisherExecutor.timeToAccept = 0;
    }

    /// @notice Proposes new external chain addresses for all protocols with 1-day time delay
    /// @param externalChainStationAddress Address-type representation for Hyperlane and LayerZero
    /// @param externalChainStationAddressString String representation for Axelar protocol
    function proposeExternalChainAddress(
        address externalChainStationAddress,
        string calldata externalChainStationAddressString
    ) external onlyAdmin {
        if (fuseSetExternalChainAddress == 0x01) revert();

        externalChainAddressChangeProposal = Structs
            .ChangeExternalChainAddressParams({
                porposeAddress_AddressType: externalChainStationAddress,
                porposeAddress_StringType: externalChainStationAddressString,
                timeToAccept: block.timestamp + 1 minutes
            });
    }

    /// @notice Cancels a pending external chain address change proposal
    function rejectProposalExternalChainAddress() external onlyAdmin {
        externalChainAddressChangeProposal = Structs
            .ChangeExternalChainAddressParams({
                porposeAddress_AddressType: address(0),
                porposeAddress_StringType: "",
                timeToAccept: 0
            });
    }

    /// @notice Accepts pending external chain address changes across all protocols
    function acceptExternalChainAddress() external {
        if (block.timestamp < externalChainAddressChangeProposal.timeToAccept)
            revert();

        hyperlane.externalChainStationAddress = bytes32(
            uint256(
                uint160(
                    externalChainAddressChangeProposal
                        .porposeAddress_AddressType
                )
            )
        );
        layerZero.externalChainStationAddress = bytes32(
            uint256(
                uint160(
                    externalChainAddressChangeProposal
                        .porposeAddress_AddressType
                )
            )
        );
        axelar.externalChainStationAddress = externalChainAddressChangeProposal
            .porposeAddress_StringType;
        _setPeer(
            layerZero.externalChainStationEid,
            layerZero.externalChainStationAddress
        );
    }

    // Getter functions //

    /// @notice Returns the complete admin configuration including proposals and timelock
    /// @return Current admin address, proposed admin, and acceptance timestamp
    function getAdmin()
        external
        view
        returns (ProposalStructs.AddressTypeProposal memory)
    {
        return admin;
    }

    /// @notice Returns the complete Fisher executor configuration including proposals
    /// @return Current Fisher executor, proposed executor, and acceptance timestamp
    function getFisherExecutor()
        external
        view
        returns (ProposalStructs.AddressTypeProposal memory)
    {
        return fisherExecutor;
    }

    /// @notice Returns whether a given async nonce has been used for a user
    /// @param user User address to check
    /// @param nonce Nonce to check
    /// @return True if the nonce has been used
    function getIfUsedAsyncNonce(
        address user,
        uint256 nonce
    ) external view returns (bool) {
        return core.getIfUsedAsyncNonce(user, nonce);
    }

    /// @notice Returns the EVVM core contract address
    /// @return Address of the EVVM contract used for balance operations
    function getCoreAddress() external view returns (address) {
        return address(core);
    }

    /// @notice Returns the complete Hyperlane protocol configuration
    /// @return Hyperlane configuration including domain ID, external chain address, and mailbox
    function getHyperlaneConfig()
        external
        view
        returns (Structs.HyperlaneConfig memory)
    {
        return hyperlane;
    }

    /// @notice Returns the complete LayerZero protocol configuration
    /// @return LayerZero configuration including endpoint ID, external chain address, and endpoint
    function getLayerZeroConfig()
        external
        view
        returns (Structs.LayerZeroConfig memory)
    {
        return layerZero;
    }

    /// @notice Returns the complete Axelar protocol configuration
    /// @return Axelar configuration including chain name, addresses, gas service, and gateway
    function getAxelarConfig()
        external
        view
        returns (Structs.AxelarConfig memory)
    {
        return axelar;
    }

    /// @notice Returns the LayerZero execution options configuration
    /// @return Encoded options bytes for LayerZero message execution (200k gas limit)
    function getOptions() external view returns (bytes memory) {
        return options;
    }

    // Internal Functions //

    /// @notice Decodes cross-chain payload and credits EVVM balance
    /// @dev Extracts token, recipient, and amount from payload and adds to EVVM balance
    /// @param payload Encoded transfer data containing token, recipient, and amount
    function decodeAndDeposit(bytes calldata payload) internal {
        (address token, address from, uint256 amount) = PayloadUtils
            .decodePayload(payload);
        executerCore(true, from, token, amount);
    }

    /// @notice Executes EVVM balance operations (add or remove)
    /// @dev Interface to EVVM's addAmountToUser and removeAmountFromUser functions
    /// @param typeOfExecution True to add balance, false to remove balance
    /// @param userToExecute Address whose balance will be modified
    /// @param token Token contract address for the balance operation
    /// @param amount Amount to add or remove from the user's balance
    function executerCore(
        bool typeOfExecution,
        address userToExecute,
        address token,
        uint256 amount
    ) internal {
        if (typeOfExecution) {
            // true = add
            core.addAmountToUser(userToExecute, token, amount);
        } else {
            // false = remove
            core.removeAmountFromUser(userToExecute, token, amount);
        }
    }

    /// @notice Disabled ownership transfer function for security
    /// @dev Ownership changes must go through the time-delayed admin proposal system
    function transferOwnership(
        address newOwner
    ) public virtual override onlyOwner {}

    /// @notice Disabled ownership renouncement function for security
    /// @dev Prevents accidental loss of administrative control over the contract
    function renounceOwnership() public virtual override onlyOwner {}
}
