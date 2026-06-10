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
    ExternalChainStationStructs as Structs
} from "@evvm/testnet-contracts/library/structs/ExternalChainStationStructs.sol";
import {
    PayloadUtils
} from "@evvm/testnet-contracts/contracts/treasuryTwoChains/lib/PayloadUtils.sol";

import {CoreError} from "@evvm/testnet-contracts/library/errors/CoreError.sol";

import {
    SignatureRecover
} from "@evvm/testnet-contracts/library/primitives/SignatureRecover.sol";
import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";
import {
    AdvancedStrings
} from "@evvm/testnet-contracts/library/utils/AdvancedStrings.sol";

import {IERC20} from "@evvm/testnet-contracts/library/primitives/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";
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
                                                             
    ______     __                        __        __          _     
   / _____  __/ /____  _________  ____ _/ /  _____/ /_  ____ _(_____ 
  / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / ___/ __ \/ __ `/ / __ \
 / /____>  </ /_/  __/ /  / / / / /_/ / /  / /__/ / / / /_/ / / / / /
/_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/   \___/_/ /_/\__,_/_/_/ /_/ 
                                                                      
 * @title EVVM External Chain Station
 * @author Mate labs
 * @notice Manages cross-chain deposits from an external chain to the EVVM host chain.
 * @dev Multi-protocol bridge supporting Hyperlane, LayerZero V2, and Axelar. 
 *      Facilitates token transfers using a sequential nonce system and ECDSA signatures.
 */

contract TreasuryExternalChainStation is
    OApp,
    OAppOptionsType3,
    AxelarExecutable
{
    /// @notice Admin address management with time-delayed proposals
    /// @dev Stores current admin, proposed admin, and acceptance timestamp
    ProposalStructs.AddressTypeProposal admin;

    /// @notice Fisher executor address management with time-delayed proposals
    ProposalStructs.AddressTypeProposal fisherExecutor;

    /// @notice Hyperlane protocol configuration for cross-chain messaging
    /// @dev Contains domain ID, host chain address, and mailbox contract address
    Structs.HyperlaneConfig hyperlane;

    /// @notice LayerZero protocol configuration for omnichain messaging
    /// @dev Contains endpoint ID, host chain address, and endpoint contract address
    Structs.LayerZeroConfig layerZero;

    /// @notice Axelar protocol configuration for cross-chain communication
    /// @dev Contains chain name, host chain address, gas service, and gateway addresses
    Structs.AxelarConfig axelar;

    /// @notice Pending proposal for changing host chain addresses across all protocols
    /// @dev Used for coordinated updates to host chain addresses with time delay
    Structs.ChangeHostChainAddressParams hostChainAddress;

    /// @notice Unique identifier for the EVVM instance this station belongs to
    /// @dev Immutable value set at deployment for signature verification
    uint256 evvmID;

    uint256 windowTimeToChangeEvvmID;

    mapping(address user => mapping(uint256 nonce => bool isUsed)) asyncNonce;

    /// @notice LayerZero execution options with gas limit configuration
    /// @dev Pre-built options for LayerZero message execution (200k gas limit)
    bytes options =
        OptionsBuilder.addExecutorLzReceiveOption(
            OptionsBuilder.newOptions(),
            200_000,
            0
        );

    /// @notice One-time fuse for setting initial host chain addresses
    bytes1 fuseSetHostChainAddress = 0x01;

    /// @notice Emitted when Fisher bridge sends tokens from external to host chain
    /// @param from Original sender address on external chain
    /// @param addressToReceive Recipient address on host chain
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

    /// @notice Initializes the External Chain Station with cross-chain protocol configurations
    /// @dev Sets up Hyperlane, LayerZero, and Axelar configurations for multi-protocol support
    /// @param _admin Initial admin address with full administrative privileges
    /// @param _crosschainConfig Configuration struct containing all cross-chain protocol settings
    constructor(
        address _admin,
        Structs.CrosschainConfig memory _crosschainConfig
    )
        OApp(_crosschainConfig.layerZero.endpointAddress, _admin)
        Ownable(_admin)
        AxelarExecutable(_crosschainConfig.axelar.gatewayAddress)
    {
        admin = ProposalStructs.AddressTypeProposal({
            current: _admin,
            proposal: address(0),
            timeToAccept: 0
        });
        hyperlane = Structs.HyperlaneConfig({
            hostChainStationDomainId: _crosschainConfig
                .hyperlane
                .hostChainStationDomainId,
            hostChainStationAddress: "",
            mailboxAddress: _crosschainConfig.hyperlane.mailboxAddress
        });
        layerZero = Structs.LayerZeroConfig({
            hostChainStationEid: _crosschainConfig
                .layerZero
                .hostChainStationEid,
            hostChainStationAddress: "",
            endpointAddress: _crosschainConfig.layerZero.endpointAddress
        });
        axelar = Structs.AxelarConfig({
            hostChainStationChainName: _crosschainConfig
                .axelar
                .hostChainStationChainName,
            hostChainStationAddress: "",
            gasServiceAddress: _crosschainConfig.axelar.gasServiceAddress,
            gatewayAddress: _crosschainConfig.axelar.gatewayAddress
        });
    }

    /// @notice One-time setup of host chain station address across all protocols
    /// @dev Can only be called once (protected by fuseSetHostChainAddress)
    /// @param hostChainStationAddress Address-type representation for Hyperlane and LayerZero
    /// @param hostChainStationAddressString String representation for Axelar protocol
    function _setHostChainAddress(
        address hostChainStationAddress,
        string calldata hostChainStationAddressString
    ) external onlyAdmin {
        if (fuseSetHostChainAddress != 0x01) revert();

        hyperlane.hostChainStationAddress = bytes32(
            uint256(uint160(hostChainStationAddress))
        );
        layerZero.hostChainStationAddress = bytes32(
            uint256(uint160(hostChainStationAddress))
        );
        axelar.hostChainStationAddress = hostChainStationAddressString;
        _setPeer(
            layerZero.hostChainStationEid,
            layerZero.hostChainStationAddress
        );

        hostChainAddress.currentAddress = hostChainStationAddress;

        fuseSetHostChainAddress = 0x00;
    }

    /**
     * @notice Updates the EVVM ID with a new value, restricted to admin and time-limited
     * @dev Allows the admin to change the EVVM ID within a 1-day window after deployment
     */
    function setEvvmID(uint256 newEvvmID) external onlyAdmin {
        if (evvmID != 0) {
            if (block.timestamp > windowTimeToChangeEvvmID)
                revert Error.WindowToChangeEvvmIDExpired();
        }

        evvmID = newEvvmID;

        windowTimeToChangeEvvmID = block.timestamp + 24 hours;
    }

    /**
     * @notice Transfers ERC20 tokens from the caller and bridges them to the host chain via the selected protocol.
     * @param toAddress Recipient on host chain
     * @param token ERC20 token address
     * @param amount Amount to bridge
     * @param protocolToExecute 0x01=Hyperlane, 0x02=LayerZero, 0x03=Axelar
     */
    function depositERC20(
        address toAddress,
        address token,
        uint256 amount,
        bytes1 protocolToExecute
    ) external payable {
        bytes memory payload = PayloadUtils.encodePayload(
            token,
            toAddress,
            amount
        );
        verifyAndDepositERC20(token, amount);
        if (protocolToExecute == 0x01) {
            // 0x01 = Hyperlane
            uint256 quote = getQuoteHyperlane(toAddress, token, amount);
            /*messageId = */ IMailbox(hyperlane.mailboxAddress).dispatch{
                value: quote
            }(
                hyperlane.hostChainStationDomainId,
                hyperlane.hostChainStationAddress,
                payload
            );
        } else if (protocolToExecute == 0x02) {
            // 0x02 = LayerZero
            uint256 quote = quoteLayerZero(toAddress, token, amount);
            _lzSend(
                layerZero.hostChainStationEid,
                payload,
                options,
                MessagingFee(quote, 0),
                msg.sender // Refund any excess fees to the sender.
            );
        } else if (protocolToExecute == 0x03) {
            // 0x03 = Axelar
            IAxelarGasService(axelar.gasServiceAddress)
                .payNativeGasForContractCall{value: msg.value}(
                address(this),
                axelar.hostChainStationChainName,
                axelar.hostChainStationAddress,
                payload,
                msg.sender
            );
            gateway().callContract(
                axelar.hostChainStationChainName,
                axelar.hostChainStationAddress,
                payload
            );
        } else {
            revert();
        }
    }

    /**
     * @notice Bridges native ETH to the host chain via the selected protocol.
     * @dev msg.value must cover both the amount and the cross-chain protocol fee.
     * @param toAddress Recipient on host chain
     * @param amount ETH amount to bridge
     * @param protocolToExecute 0x01=Hyperlane, 0x02=LayerZero, 0x03=Axelar
     */
    function depositCoin(
        address toAddress,
        uint256 amount,
        bytes1 protocolToExecute
    ) external payable {
        if (msg.value < amount) revert Error.InsufficientBalance();

        bytes memory payload = PayloadUtils.encodePayload(
            address(0),
            toAddress,
            amount
        );

        if (protocolToExecute == 0x01) {
            // 0x01 = Hyperlane
            uint256 quote = getQuoteHyperlane(toAddress, address(0), amount);
            if (msg.value < quote + amount) revert Error.InsufficientBalance();
            /*messageId = */ IMailbox(hyperlane.mailboxAddress).dispatch{
                value: quote
            }(
                hyperlane.hostChainStationDomainId,
                hyperlane.hostChainStationAddress,
                payload
            );
        } else if (protocolToExecute == 0x02) {
            // 0x02 = LayerZero
            uint256 fee = quoteLayerZero(toAddress, address(0), amount);
            if (msg.value < fee + amount) revert Error.InsufficientBalance();
            _lzSend(
                layerZero.hostChainStationEid,
                payload,
                options,
                MessagingFee(fee, 0),
                msg.sender // Refund any excess fees to the sender.
            );
        } else if (protocolToExecute == 0x03) {
            // 0x03 = Axelar
            IAxelarGasService(axelar.gasServiceAddress)
                .payNativeGasForContractCall{value: msg.value - amount}(
                address(this),
                axelar.hostChainStationChainName,
                axelar.hostChainStationAddress,
                payload,
                msg.sender
            );
            gateway().callContract(
                axelar.hostChainStationChainName,
                axelar.hostChainStationAddress,
                payload
            );
        } else {
            revert();
        }
    }

    /**
     * @notice Confirms a Fisher bridge withdrawal from the host chain by validating the sender's signature.
     * @dev Uses the independent asyncNonce mapping (not Core.sol); marks nonce used after validation.
     * @param from Original sender on host chain
     * @param addressToReceive Recipient on external chain
     * @param tokenAddress Token address (address(0) for ETH)
     * @param priorityFee Fee for priority processing
     * @param amount Token amount received
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
        if (asyncNonce[from][nonce]) revert CoreError.AsyncNonceAlreadyUsed();

        if (
            SignatureRecover.recoverSigner(
                AdvancedStrings.buildSignaturePayload(
                    evvmID,
                    hostChainAddress.currentAddress,
                    Hash.hashDataForFisherBridge(
                        addressToReceive,
                        tokenAddress,
                        priorityFee,
                        amount
                    ),
                    fisherExecutor.current,
                    nonce,
                    true
                ),
                signature
            ) != from
        ) revert CoreError.InvalidSignature();

        asyncNonce[from][nonce] = true;
    }

    /**
     * @notice Accepts ERC20 tokens from the caller and emits a Fisher bridge deposit event for the host chain.
     * @dev Validates ECDSA signature, marks asyncNonce used, and holds tokens in this contract.
     * @param from Original sender (signer)
     * @param addressToReceive Recipient on host chain
     * @param tokenAddress ERC20 token address
     * @param priorityFee Fee for priority processing
     * @param amount Amount to bridge
     * @param nonce Async nonce from user
     * @param signature ECDSA signature from `from`
     */
    function fisherBridgeSendERC20(
        address from,
        address addressToReceive,
        address tokenAddress,
        uint256 priorityFee,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external onlyFisherExecutor {
        if (asyncNonce[from][nonce]) revert CoreError.AsyncNonceAlreadyUsed();

        if (
            SignatureRecover.recoverSigner(
                AdvancedStrings.buildSignaturePayload(
                    evvmID,
                    fisherExecutor.current,
                    Hash.hashDataForFisherBridge(
                        addressToReceive,
                        tokenAddress,
                        priorityFee,
                        amount
                    ),
                    fisherExecutor.current,
                    nonce,
                    true
                ),
                signature
            ) != from
        ) revert CoreError.InvalidSignature();

        verifyAndDepositERC20(tokenAddress, amount);

        asyncNonce[from][nonce] = true;

        emit FisherBridgeSend(
            from,
            addressToReceive,
            tokenAddress,
            priorityFee,
            amount,
            nonce
        );
    }

    /**
     * @notice Accepts ETH from the executor and emits a Fisher bridge deposit event for the host chain.
     * @dev msg.value must equal amount + priorityFee. Validates ECDSA signature and marks nonce used.
     * @param from Original sender (signer)
     * @param addressToReceive Recipient on host chain
     * @param priorityFee Fee for priority processing
     * @param amount ETH amount to bridge
     * @param nonce Async nonce from user
     * @param signature ECDSA signature from `from`
     */
    function fisherBridgeSendCoin(
        address from,
        address addressToReceive,
        uint256 priorityFee,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature
    ) external payable onlyFisherExecutor {
        if (asyncNonce[from][nonce]) revert CoreError.AsyncNonceAlreadyUsed();

        if (
            SignatureRecover.recoverSigner(
                AdvancedStrings.buildSignaturePayload(
                    evvmID,
                    fisherExecutor.current,
                    Hash.hashDataForFisherBridge(
                        addressToReceive,
                        address(0),
                        priorityFee,
                        amount
                    ),
                    fisherExecutor.current,
                    nonce,
                    true
                ),
                signature
            ) != from
        ) revert CoreError.InvalidSignature();

        if (msg.value != amount + priorityFee)
            revert Error.InsufficientBalance();

        asyncNonce[from][nonce] = true;

        emit FisherBridgeSend(
            from,
            addressToReceive,
            address(0),
            priorityFee,
            amount,
            nonce
        );
    }

    // Hyperlane Specific Functions //

    /**
     * @notice Returns the fee required to send a Hyperlane message to the host chain.
     * @param toAddress Recipient on host chain
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to bridge
     * @return Native token fee for the Hyperlane message
     */
    function getQuoteHyperlane(
        address toAddress,
        address token,
        uint256 amount
    ) public view returns (uint256) {
        return
            IMailbox(hyperlane.mailboxAddress).quoteDispatch(
                hyperlane.hostChainStationDomainId,
                hyperlane.hostChainStationAddress,
                PayloadUtils.encodePayload(token, toAddress, amount)
            );
    }

    /**
     * @notice Handles incoming Hyperlane messages from the host chain and transfers tokens to the recipient.
     * @dev Validates mailbox caller, origin domain, and sender address before calling decodeAndGive.
     * @param _origin Source chain domain ID
     * @param _sender Sender address (host station)
     * @param _data Encoded payload (token, to, amount)
     */
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _data
    ) external payable virtual {
        if (msg.sender != hyperlane.mailboxAddress)
            revert Error.MailboxNotAuthorized();

        if (_sender != hyperlane.hostChainStationAddress)
            revert Error.SenderNotAuthorized();

        if (_origin != hyperlane.hostChainStationDomainId)
            revert Error.ChainIdNotAuthorized();

        decodeAndGive(_data);
    }

    // LayerZero Specific Functions //

    /**
     * @notice Returns the fee required to send a LayerZero message to the host chain.
     * @param toAddress Recipient on host chain
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to bridge
     * @return Native token fee for the LayerZero message
     */
    function quoteLayerZero(
        address toAddress,
        address token,
        uint256 amount
    ) public view returns (uint256) {
        MessagingFee memory fee = _quote(
            layerZero.hostChainStationEid,
            PayloadUtils.encodePayload(token, toAddress, amount),
            options,
            false
        );
        return fee.nativeFee;
    }

    /**
     * @notice Handles incoming LayerZero messages from the host chain and transfers tokens to the recipient.
     * @dev Validates source EID and sender address before calling decodeAndGive.
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
        if (_origin.srcEid != layerZero.hostChainStationEid)
            revert Error.ChainIdNotAuthorized();

        if (_origin.sender != layerZero.hostChainStationAddress)
            revert Error.SenderNotAuthorized();

        decodeAndGive(message);
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
     * @notice Handles incoming Axelar messages from the host chain and transfers tokens to the recipient.
     * @dev Validates source chain name and address before calling decodeAndGive.
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
                axelar.hostChainStationChainName
            )
        ) revert Error.ChainIdNotAuthorized();

        if (
            !AdvancedStrings.equal(
                _sourceAddress,
                axelar.hostChainStationAddress
            )
        ) revert Error.SenderNotAuthorized();

        decodeAndGive(_payload);
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

    /// @notice Proposes new host chain addresses for all protocols with 1-day time delay
    /// @param hostChainStationAddress Address-type representation for Hyperlane and LayerZero
    /// @param hostChainStationAddressString String representation for Axelar protocol
    function proposeHostChainAddress(
        address hostChainStationAddress,
        string calldata hostChainStationAddressString
    ) external onlyAdmin {
        if (fuseSetHostChainAddress == 0x01) revert();

        hostChainAddress = Structs.ChangeHostChainAddressParams({
            porposeAddress_AddressType: hostChainStationAddress,
            porposeAddress_StringType: hostChainStationAddressString,
            currentAddress: hostChainAddress.currentAddress,
            timeToAccept: block.timestamp + 1 minutes
        });
    }

    /// @notice Cancels a pending host chain address change proposal
    function rejectProposalHostChainAddress() external onlyAdmin {
        hostChainAddress = Structs.ChangeHostChainAddressParams({
            porposeAddress_AddressType: address(0),
            porposeAddress_StringType: "",
            currentAddress: hostChainAddress.currentAddress,
            timeToAccept: 0
        });
    }

    /// @notice Accepts pending host chain address changes across all protocols
    function acceptHostChainAddress() external {
        if (block.timestamp < hostChainAddress.timeToAccept) revert();

        hyperlane.hostChainStationAddress = bytes32(
            uint256(uint160(hostChainAddress.porposeAddress_AddressType))
        );
        layerZero.hostChainStationAddress = bytes32(
            uint256(uint160(hostChainAddress.porposeAddress_AddressType))
        );
        axelar.hostChainStationAddress = hostChainAddress
            .porposeAddress_StringType;

        _setPeer(
            layerZero.hostChainStationEid,
            layerZero.hostChainStationAddress
        );

        hostChainAddress = Structs.ChangeHostChainAddressParams({
            porposeAddress_AddressType: address(0),
            porposeAddress_StringType: "",
            currentAddress: hostChainAddress.porposeAddress_AddressType,
            timeToAccept: 0
        });
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

    /// @notice Returns the complete Fisher executor configuration including proposals and timelock
    /// @return Current Fisher executor address, proposed executor, and acceptance timestamp
    function getFisherExecutor()
        external
        view
        returns (ProposalStructs.AddressTypeProposal memory)
    {
        return fisherExecutor;
    }

    function getIfUsedAsyncNonce(
        address user,
        uint256 nonce
    ) public view virtual returns (bool) {
        return asyncNonce[user][nonce];
    }

    /// @notice Returns the complete Hyperlane protocol configuration
    /// @return Hyperlane configuration including domain ID, host chain address, and mailbox
    function getHyperlaneConfig()
        external
        view
        returns (Structs.HyperlaneConfig memory)
    {
        return hyperlane;
    }

    /// @notice Returns the complete LayerZero protocol configuration
    /// @return LayerZero configuration including endpoint ID, host chain address, and endpoint
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

    /// @notice Decodes cross-chain payload and executes the token transfer
    /// @dev Handles both ETH (address(0)) and ERC20 token transfers to recipients
    /// @param payload Encoded transfer data containing token, recipient, and amount
    function decodeAndGive(bytes calldata payload) internal {
        (address token, address toAddress, uint256 amount) = PayloadUtils
            .decodePayload(payload);
        if (token == address(0))
            SafeTransferLib.safeTransferETH(toAddress, amount);
        else IERC20(token).transfer(toAddress, amount);
    }

    /// @notice Validates and deposits ERC20 tokens from the caller
    /// @dev Verifies token approval and executes transferFrom to this contract
    /// @param token ERC20 token contract address (cannot be address(0))
    /// @param amount Amount of tokens to deposit and hold in this contract
    function verifyAndDepositERC20(address token, uint256 amount) internal {
        if (token == address(0)) revert();
        if (IERC20(token).allowance(msg.sender, address(this)) < amount)
            revert Error.InsufficientBalance();

        IERC20(token).transferFrom(msg.sender, address(this), amount);
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
