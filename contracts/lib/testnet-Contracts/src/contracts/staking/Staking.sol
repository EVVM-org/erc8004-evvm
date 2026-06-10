// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;

import {
    StakingError as Error
} from "@evvm/testnet-contracts/library/errors/StakingError.sol";
import {
    StakingHashUtils as Hash
} from "@evvm/testnet-contracts/library/utils/signature/StakingHashUtils.sol";
import {
    StakingStructs as Structs
} from "@evvm/testnet-contracts/library/structs/StakingStructs.sol";

import {Core} from "@evvm/testnet-contracts/contracts/core/Core.sol";
import {
    Estimator
} from "@evvm/testnet-contracts/contracts/staking/Estimator.sol";

import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";

/**


  /$$$$$$  /$$             /$$      /$$                  
 /$$__  $$| $$            | $$     |__/                  
| $$  \__/$$$$$$   /$$$$$$| $$   /$$/$$/$$$$$$$  /$$$$$$ 
|  $$$$$|_  $$_/  |____  $| $$  /$$| $| $$__  $$/$$__  $$
 \____  $$| $$     /$$$$$$| $$$$$$/| $| $$  \ $| $$  \ $$
 /$$  \ $$| $$ /$$/$$__  $| $$_  $$| $| $$  | $| $$  | $$
|  $$$$$$/|  $$$$|  $$$$$$| $$ \  $| $| $$  | $|  $$$$$$$
 \______/  \___/  \_______|__/  \__|__|__/  |__/\____  $$
                                                /$$  \ $$
                                               |  $$$$$$/
                                                \______/                                                                                       

████████╗███████╗███████╗████████╗███╗   ██╗███████╗████████╗
╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝████╗  ██║██╔════╝╚══██╔══╝
   ██║   █████╗  ███████╗   ██║   ██╔██╗ ██║█████╗     ██║   
   ██║   ██╔══╝  ╚════██║   ██║   ██║╚██╗██║██╔══╝     ██║   
   ██║   ███████╗███████║   ██║   ██║ ╚████║███████╗   ██║   
   ╚═╝   ╚══════╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝╚══════╝   ╚═╝   
 * @title EVVM Staking
 * @author Mate labs
 * @notice Validator staking mechanism for the EVVM ecosystem.
 * @dev Manages staking, unstaking, and yield distribution via the Estimator contract. 
 *      Supports presale and public staking phases with time-locked security and nonce-based replay protection.
 */

contract Staking {
    uint256 constant TIME_TO_ACCEPT_PROPOSAL = 1 days;

    /// @dev Address of the EVVM core contract
    address private EVVM_ADDRESS;

    /// @dev Maximum number of presale stakers allowed
    uint256 private constant LIMIT_PRESALE_STAKER = 800;
    /// @dev Current count of registered presale stakers
    uint256 private presaleStakerCount;
    /// @dev Price of one staking main token (5083 main token = 1 staking)
    uint256 private constant PRICE_OF_STAKING = 5083 * (10 ** 18);

    /// @dev Admin address management with proposal system
    ProposalStructs.AddressTypeProposal private admin;
    /// @dev Golden Fisher address management with proposal system
    ProposalStructs.AddressTypeProposal private goldenFisher;
    /// @dev Estimator contract address management with proposal system
    ProposalStructs.AddressTypeProposal private estimatorAddress;
    /// @dev Time delay for regular staking after unstaking
    ProposalStructs.UintTypeProposal private secondsToUnlockStaking;
    /// @dev Time delay for full unstaking (21 days default)
    ProposalStructs.UintTypeProposal private secondsToUnllockFullUnstaking;
    /// @dev Flag to enable/disable presale staking
    ProposalStructs.BoolTypeProposal private allowPresaleStaking;
    /// @dev Flag to enable/disable public staking
    ProposalStructs.BoolTypeProposal private allowPublicStaking;
    /// @dev Variable to store service staking metadata
    Structs.ServiceStakingMetadata private serviceStakingData;

    /// @dev One-time setup breaker for estimator and EVVM addresses
    bytes1 private breakerSetupEstimatorAndEvvm;

    /// @dev Mapping to store presale staker metadata
    mapping(address => Structs.PresaleStakerMetadata) private userPresaleStaker;

    /// @dev Mapping to store complete staking history for each user
    mapping(address => Structs.HistoryMetadata[]) private userHistory;

    Core private core;
    Estimator private estimator;

    /// @dev Modifier to verify access to admin functions
    modifier onlyOwner() {
        if (msg.sender != admin.current) revert Error.SenderIsNotAdmin();

        _;
    }

    /// @dev Modifier to verify access to a contract or service account
    modifier onlyCA() {
        uint256 size;
        address callerAddress = msg.sender;

        assembly {
            /// @dev check the size of the opcode of the address
            size := extcodesize(callerAddress)
        }

        if (size == 0) revert Error.AddressIsNotAService();

        _;
    }

    /**
     * @notice Initializes the staking contract.
     * @param initialAdmin System administrator.
     * @param initialGoldenFisher Authorized Golden Fisher address.
     */
    constructor(address initialAdmin, address initialGoldenFisher) {
        admin.current = initialAdmin;

        goldenFisher.current = initialGoldenFisher;

        allowPublicStaking.flag = true;
        allowPresaleStaking.flag = false;

        secondsToUnlockStaking.current = 0;

        secondsToUnllockFullUnstaking.current = 5 days;

        breakerSetupEstimatorAndEvvm = 0x01;
    }

    /**
     * @notice Configures system contract integrations once.
     * @param _estimator Estimator contract address (yield calculations).
     * @param _core EVVM Core contract address (payments).
     */
    function initializeSystemContracts(
        address _estimator,
        address _core
    ) external {
        if (breakerSetupEstimatorAndEvvm == 0x00) revert();

        estimatorAddress.current = _estimator;
        EVVM_ADDRESS = _core;

        core = Core(_core);
        estimator = Estimator(_estimator);
        breakerSetupEstimatorAndEvvm = 0x00;
    }

    /**
     * @notice Unlimited staking/unstaking for the Golden Fisher.
     * @dev Uses sync nonces for coordination with Core operations.
     * @param isStaking True to stake, false to unstake.
     * @param amountOfStaking Number of staking tokens.
     * @param signaturePay Authorization signature for Core payment.
     */
    function goldenStaking(
        bool isStaking,
        uint256 amountOfStaking,
        bytes calldata signaturePay
    ) external {
        if (msg.sender != goldenFisher.current)
            revert Error.SenderIsNotGoldenFisher();

        stakingBaseProcess(
            Structs.AccountMetadata({
                Address: goldenFisher.current,
                IsAService: false
            }),
            address(0),
            isStaking,
            amountOfStaking,
            0,
            core.getNextCurrentSyncNonce(msg.sender),
            false,
            signaturePay
        );
    }

    /**
     * @notice White-listed presale staking (max 2 tokens per user).
     * @param user Participant address.
     * @param isStaking True to stake, false to unstake.
     * @param nonce Async nonce for signature verification.
     * @param signature Participant's authorization signature.
     * @param priorityFeePay Optional priority fee.
     * @param noncePay Nonce for the Core payment.
     * @param signaturePay Signature for the Core payment.
     */
    function presaleStaking(
        address user,
        bool isStaking,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        if (!allowPresaleStaking.flag || allowPublicStaking.flag)
            revert Error.PresaleStakingDisabled();

        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForPresaleStake(isStaking, 1),
            originExecutor,
            nonce,
            true,
            signature
        );

        if (!userPresaleStaker[user].isAllow)
            revert Error.UserIsNotPresaleStaker();

        uint256 current = userPresaleStaker[user].stakingAmount;

        if (isStaking ? current >= 2 : current == 0)
            revert Error.UserPresaleStakerLimitExceeded();

        userPresaleStaker[user].stakingAmount = isStaking
            ? current + 1
            : current - 1;

        stakingBaseProcess(
            Structs.AccountMetadata({Address: user, IsAService: false}),
            originExecutor,
            isStaking,
            1,
            priorityFeePay,
            noncePay,
            true,
            signaturePay
        );
    }

    /**
     * @notice Public staking open to any user when enabled.
     * @param user Participant address.
     * @param isStaking True to stake, false to unstake.
     * @param amountOfStaking Number of tokens.
     * @param nonce Async nonce for signature verification.
     * @param signature Participant's authorization signature.
     * @param priorityFeePay Optional priority fee.
     * @param noncePay Nonce for the Core payment.
     * @param signaturePay Signature for the Core payment.
     */
    function publicStaking(
        address user,
        bool isStaking,
        uint256 amountOfStaking,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external {
        if (!allowPublicStaking.flag) revert Error.PublicStakingDisabled();

        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForPublicStake(isStaking, amountOfStaking),
            originExecutor,
            nonce,
            true,
            signature
        );

        stakingBaseProcess(
            Structs.AccountMetadata({Address: user, IsAService: false}),
            originExecutor,
            isStaking,
            amountOfStaking,
            priorityFeePay,
            noncePay,
            true,
            signaturePay
        );
    }

    /**
     * @notice Step 1 of atomic service staking: snapshots balances before payment.
     * @dev Must be called in the same transaction as Core.caPay and confirmServiceStaking.
     *      Only callable by contract accounts.
     * @param amountOfStaking Number of staking tokens to acquire.
     */
    function prepareServiceStaking(uint256 amountOfStaking) external onlyCA {
        serviceStakingData = Structs.ServiceStakingMetadata({
            service: msg.sender,
            timestamp: block.timestamp,
            amountOfStaking: amountOfStaking,
            amountServiceBeforeStaking: core.getBalance(
                msg.sender,
                core.getPrincipalTokenAddress()
            ),
            amountStakingBeforeStaking: core.getBalance(
                address(this),
                core.getPrincipalTokenAddress()
            )
        });
    }

    /**
     * @notice Step 3 of atomic service staking: verifies the payment occurred and completes staking.
     * @dev Reverts if called outside the same transaction as prepareServiceStaking,
     *      if msg.sender differs, or if the balance delta does not match the required amount.
     *      Only callable by contract accounts.
     */
    function confirmServiceStaking() external onlyCA {
        uint256 totalStakingRequired = PRICE_OF_STAKING *
            serviceStakingData.amountOfStaking;

        if (
            serviceStakingData.amountServiceBeforeStaking -
                totalStakingRequired !=
            core.getBalance(msg.sender, core.getPrincipalTokenAddress()) &&
            serviceStakingData.amountStakingBeforeStaking +
                totalStakingRequired !=
            core.getBalance(address(this), core.getPrincipalTokenAddress())
        )
            revert Error.ServiceDoesNotFulfillCorrectStakingAmount(
                totalStakingRequired
            );

        if (serviceStakingData.timestamp != block.timestamp)
            revert Error.ServiceDoesNotStakeInSameTx();

        if (serviceStakingData.service != msg.sender)
            revert Error.AddressMismatch();

        stakingBaseProcess(
            Structs.AccountMetadata({Address: msg.sender, IsAService: true}),
            address(0),
            true,
            serviceStakingData.amountOfStaking,
            0,
            0,
            false,
            ""
        );
    }

    /**
     * @notice Unstakes tokens for a contract account without signature or payment.
     * @dev Subject to the same time-lock as regular unstaking. Only callable by contract accounts.
     * @param amountOfStaking Amount of staking tokens to unstake.
     */
    function serviceUnstaking(uint256 amountOfStaking) external onlyCA {
        stakingBaseProcess(
            Structs.AccountMetadata({Address: msg.sender, IsAService: true}),
            address(0),
            false,
            amountOfStaking,
            0,
            0,
            false,
            ""
        );
    }

    /**
     * @notice Core staking logic that handles both service and user staking operations
     * @dev Processes payments, updates history, handles time locks, and manages EVVM integration
     * @param account Metadata of the account performing the staking operation
     *                  - Address: Address of the account
     *                  - IsAService: Boolean indicating if the account is a smart contract (service) account
     * @param isStaking True for staking (requires payment), false for unstaking (provides refund)
     * @param amountOfStaking Amount of staking tokens to stake/unstake
     * @param priorityFeePay Priority fee for EVVM transaction
     * @param noncePay Nonce for EVVM contract transaction
     * @param signaturePay Signature for EVVM contract transaction
     */
    function stakingBaseProcess(
        Structs.AccountMetadata memory account,
        address originExecutor,
        bool isStaking,
        uint256 amountOfStaking,
        uint256 priorityFeePay,
        uint256 noncePay,
        bool isAsyncExecEvvm,
        bytes memory signaturePay
    ) internal {
        uint256 auxSMsteBalance;

        if (isStaking) {
            if (
                getTimeToUserUnlockStakingTime(account.Address) >
                block.timestamp
            ) revert Error.AddressMustWaitToStakeAgain();

            if (!account.IsAService)
                requestPay(
                    account.Address,
                    (PRICE_OF_STAKING * amountOfStaking),
                    priorityFeePay,
                    originExecutor,
                    noncePay,
                    isAsyncExecEvvm,
                    signaturePay
                );

            core.pointStaker(account.Address, 0x01);

            auxSMsteBalance = userHistory[account.Address].length == 0
                ? amountOfStaking
                : userHistory[account.Address][
                    userHistory[account.Address].length - 1
                ].totalStaked + amountOfStaking;
        } else {
            if (amountOfStaking == getUserAmountStaked(account.Address)) {
                if (
                    getTimeToUserUnlockFullUnstakingTime(account.Address) >
                    block.timestamp
                ) revert Error.AddressMustWaitToFullUnstake();

                core.pointStaker(account.Address, 0x00);
            }

            if (priorityFeePay != 0 && !account.IsAService)
                requestPay(
                    account.Address,
                    0,
                    priorityFeePay,
                    originExecutor,
                    noncePay,
                    isAsyncExecEvvm,
                    signaturePay
                );

            auxSMsteBalance =
                userHistory[account.Address][
                    userHistory[account.Address].length - 1
                ].totalStaked -
                amountOfStaking;

            makeCaPay(
                core.getPrincipalTokenAddress(),
                account.Address,
                (PRICE_OF_STAKING * amountOfStaking)
            );
        }

        userHistory[account.Address].push(
            Structs.HistoryMetadata({
                transactionType: isStaking
                    ? bytes32(uint256(1))
                    : bytes32(uint256(2)),
                amount: amountOfStaking,
                timestamp: block.timestamp,
                totalStaked: auxSMsteBalance
            })
        );

        if (core.isAddressStaker(msg.sender) && !account.IsAService) {
            makeCaPay(
                core.getPrincipalTokenAddress(),
                msg.sender,
                (core.getRewardAmount() * 2) + priorityFeePay
            );
        }
    }

    /**
     * @notice Allows users to claim their staking rewards (yield)
     * @dev Interacts with the Estimator contract to calculate and distribute rewards
     * @param user Address of the user claiming rewards
     * @return epochAnswer Epoch identifier for the reward calculation
     * @return tokenToBeRewarded Address of the token being rewarded
     * @return amountTotalToBeRewarded Total amount of rewards to be distributed
     * @return idToOverwriteUserHistory Index in user history to update with reward info
     * @return timestampToBeOverwritten Timestamp to record for the reward transaction
     */
    function gimmeYiel(
        address user
    )
        external
        returns (
            bytes32 epochAnswer,
            address tokenToBeRewarded,
            uint256 amountTotalToBeRewarded,
            uint256 idToOverwriteUserHistory,
            uint256 timestampToBeOverwritten
        )
    {
        if (userHistory[user].length > 0) {
            (
                epochAnswer,
                tokenToBeRewarded,
                amountTotalToBeRewarded,
                idToOverwriteUserHistory,
                timestampToBeOverwritten
            ) = estimator.makeEstimation(user);

            if (amountTotalToBeRewarded > 0) {
                makeCaPay(tokenToBeRewarded, user, amountTotalToBeRewarded);

                userHistory[user][idToOverwriteUserHistory]
                    .transactionType = epochAnswer;
                userHistory[user][idToOverwriteUserHistory]
                    .amount = amountTotalToBeRewarded;
                userHistory[user][idToOverwriteUserHistory]
                    .timestamp = timestampToBeOverwritten;

                if (core.isAddressStaker(msg.sender)) {
                    makeCaPay(
                        core.getPrincipalTokenAddress(),
                        msg.sender,
                        (core.getRewardAmount() * 1)
                    );
                }
            }
        }
    }

    //▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
    // Tools for Evvm Integration
    //▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀

    /**
     * @notice Routes a Principal Token payment through Core. Supports sync/async nonces.
     * @param user Payer address.
     * @param amount Amount in Principal Tokens.
     * @param priorityFee Optional executor fee.
     * @param nonce Nonce for the Core transaction.
     * @param isAsyncExec True for async nonce, false for sync.
     * @param signature Authorization signature.
     */
    function requestPay(
        address user,
        uint256 amount,
        uint256 priorityFee,
        address originExecutor,
        uint256 nonce,
        bool isAsyncExec,
        bytes memory signature
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
            isAsyncExec,
            signature
        );
    }

    /**
     * @notice Transfers tokens to a user via Core.caPay.
     * @param tokenAddress Token to send.
     * @param user Recipient address.
     * @param amount Amount to send.
     */
    function makeCaPay(
        address tokenAddress,
        address user,
        uint256 amount
    ) internal {
        core.caPay(user, tokenAddress, amount);
    }

    //▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
    // Administrative Functions with Time-Delayed Governance
    //▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀

    /**
     * @notice Adds a single address to the presale staker allowlist.
     * @param _staker Address to add.
     */
    function addPresaleStaker(address _staker) external onlyOwner {
        if (presaleStakerCount > LIMIT_PRESALE_STAKER)
            revert Error.LimitPresaleStakersExceeded();

        userPresaleStaker[_staker].isAllow = true;
        presaleStakerCount++;
    }

    /**
     * @notice Adds multiple addresses to the presale staker allowlist in batch.
     * @param _stakers Addresses to add.
     */
    function addPresaleStakers(address[] calldata _stakers) external onlyOwner {
        for (uint256 i = 0; i < _stakers.length; i++) {
            if (presaleStakerCount > LIMIT_PRESALE_STAKER)
                revert Error.LimitPresaleStakersExceeded();

            userPresaleStaker[_stakers[i]].isAllow = true;
            presaleStakerCount++;
        }
    }

    /**
     * @notice Proposes a new admin address (1-day delay).
     * @param _newAdmin Proposed admin address.
     */
    function proposeAdmin(address _newAdmin) external onlyOwner {
        admin.proposal = _newAdmin;
        admin.timeToAccept = block.timestamp + TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the pending admin proposal.
     */
    function rejectProposalAdmin() external onlyOwner {
        admin.proposal = address(0);
        admin.timeToAccept = 0;
    }

    /**
     * @notice Accepts the admin proposal and becomes the new admin
     * @dev Can only be called by the proposed admin after the time delay has passed
     */
    function acceptNewAdmin() external {
        if (msg.sender != admin.proposal)
            revert Error.SenderIsNotProposedAdmin();

        if (admin.timeToAccept > block.timestamp)
            revert Error.TimeToAcceptProposalNotReached();

        admin.current = admin.proposal;
        admin.proposal = address(0);
        admin.timeToAccept = 0;
    }

    /**
     * @notice Proposes a new Golden Fisher address (1-day delay).
     * @param _goldenFisher Proposed Golden Fisher address.
     */
    function proposeGoldenFisher(address _goldenFisher) external onlyOwner {
        goldenFisher.proposal = _goldenFisher;
        goldenFisher.timeToAccept = block.timestamp + TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the pending Golden Fisher proposal.
     */
    function rejectProposalGoldenFisher() external onlyOwner {
        goldenFisher.proposal = address(0);
        goldenFisher.timeToAccept = 0;
    }

    /**
     * @notice Finalizes the Golden Fisher change after the time-lock.
     */
    function acceptNewGoldenFisher() external onlyOwner {
        if (goldenFisher.timeToAccept > block.timestamp)
            revert Error.TimeToAcceptProposalNotReached();

        goldenFisher.current = goldenFisher.proposal;
        goldenFisher.proposal = address(0);
        goldenFisher.timeToAccept = 0;
    }

    /**
     * @notice Proposes a new re-stake delay (seconds to wait after unstaking before staking again).
     * @param _secondsToUnlockStaking New delay in seconds.
     */
    function proposeSetSecondsToUnlockStaking(
        uint256 _secondsToUnlockStaking
    ) external onlyOwner {
        secondsToUnlockStaking.proposal = _secondsToUnlockStaking;
        secondsToUnlockStaking.timeToAccept =
            block.timestamp +
            TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the pending re-stake delay proposal.
     */
    function rejectProposalSetSecondsToUnlockStaking() external onlyOwner {
        secondsToUnlockStaking.proposal = 0;
        secondsToUnlockStaking.timeToAccept = 0;
    }

    /**
     * @notice Finalizes the re-stake delay change after the time-lock.
     */
    function acceptSetSecondsToUnlockStaking() external onlyOwner {
        if (secondsToUnlockStaking.timeToAccept > block.timestamp)
            revert Error.TimeToAcceptProposalNotReached();

        secondsToUnlockStaking.current = secondsToUnlockStaking.proposal;
        secondsToUnlockStaking.proposal = 0;
        secondsToUnlockStaking.timeToAccept = 0;
    }

    /**
     * @notice Proposes a new full-unstake time-lock duration.
     * @param _secondsToUnllockFullUnstaking New delay in seconds.
     */
    function prepareSetSecondsToUnllockFullUnstaking(
        uint256 _secondsToUnllockFullUnstaking
    ) external onlyOwner {
        secondsToUnllockFullUnstaking.proposal = _secondsToUnllockFullUnstaking;
        secondsToUnllockFullUnstaking.timeToAccept =
            block.timestamp +
            TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the pending full-unstake delay proposal.
     */
    function cancelSetSecondsToUnllockFullUnstaking() external onlyOwner {
        secondsToUnllockFullUnstaking.proposal = 0;
        secondsToUnllockFullUnstaking.timeToAccept = 0;
    }

    /**
     * @notice Finalizes the full-unstake delay change after the time-lock.
     */
    function confirmSetSecondsToUnllockFullUnstaking() external onlyOwner {
        if (secondsToUnllockFullUnstaking.timeToAccept > block.timestamp)
            revert Error.TimeToAcceptProposalNotReached();

        secondsToUnllockFullUnstaking.current = secondsToUnllockFullUnstaking
            .proposal;
        secondsToUnllockFullUnstaking.proposal = 0;
        secondsToUnllockFullUnstaking.timeToAccept = 0;
    }

    /**
     * @notice Initiates a toggle of the public staking flag (1-day delay).
     */
    function prepareChangeAllowPublicStaking() external onlyOwner {
        allowPublicStaking.timeToAccept =
            block.timestamp +
            TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the pending public staking flag toggle.
     */
    function cancelChangeAllowPublicStaking() external onlyOwner {
        allowPublicStaking.timeToAccept = 0;
    }

    /**
     * @notice Finalizes the public staking flag toggle after the time-lock.
     */
    function confirmChangeAllowPublicStaking() external onlyOwner {
        if (allowPublicStaking.timeToAccept > block.timestamp)
            revert Error.TimeToAcceptProposalNotReached();

        allowPublicStaking = ProposalStructs.BoolTypeProposal({
            flag: !allowPublicStaking.flag,
            timeToAccept: 0
        });
    }

    /**
     * @notice Initiates a toggle of the presale staking flag (1-day delay).
     */
    function prepareChangeAllowPresaleStaking() external onlyOwner {
        allowPresaleStaking.timeToAccept =
            block.timestamp +
            TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the pending presale staking flag toggle.
     */
    function cancelChangeAllowPresaleStaking() external onlyOwner {
        allowPresaleStaking.timeToAccept = 0;
    }

    /**
     * @notice Finalizes the presale staking flag toggle after the time-lock.
     */
    function confirmChangeAllowPresaleStaking() external onlyOwner {
        if (allowPresaleStaking.timeToAccept > block.timestamp)
            revert Error.TimeToAcceptProposalNotReached();

        allowPresaleStaking.flag = !allowPresaleStaking.flag;
        allowPresaleStaking.timeToAccept = 0;
    }

    /**
     * @notice Proposes a new Estimator contract address (1-day delay).
     * @param _estimator Proposed Estimator address.
     */
    function proposeEstimator(address _estimator) external onlyOwner {
        estimatorAddress.proposal = _estimator;
        estimatorAddress.timeToAccept =
            block.timestamp +
            TIME_TO_ACCEPT_PROPOSAL;
    }

    /**
     * @notice Cancels the pending Estimator proposal.
     */
    function rejectProposalEstimator() external onlyOwner {
        estimatorAddress.proposal = address(0);
        estimatorAddress.timeToAccept = 0;
    }

    /**
     * @notice Finalizes the Estimator upgrade after the time-lock.
     */
    function acceptNewEstimator() external onlyOwner {
        if (estimatorAddress.timeToAccept > block.timestamp)
            revert Error.TimeToAcceptProposalNotReached();

        estimatorAddress.current = estimatorAddress.proposal;
        estimatorAddress.proposal = address(0);
        estimatorAddress.timeToAccept = 0;
        estimator = Estimator(estimatorAddress.current);
    }

    //▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀
    // View Functions - Public Data Access
    //▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀▄▀

    /**
     * @notice Returns the full staking history for an address.
     */
    function getAddressHistory(
        address _account
    ) public view returns (Structs.HistoryMetadata[] memory) {
        return userHistory[_account];
    }

    /**
     * @notice Returns the number of entries in an address's staking history.
     */
    function getSizeOfAddressHistory(
        address _account
    ) public view returns (uint256) {
        return userHistory[_account].length;
    }

    /**
     * @notice Returns the staking history entry at the given index for an address.
     */
    function getAddressHistoryByIndex(
        address _account,
        uint256 _index
    ) public view returns (Structs.HistoryMetadata memory) {
        return userHistory[_account][_index];
    }

    /**
     * @notice Returns the fixed price of one staking token (5083 × 10^18 Principal Tokens).
     */
    function priceOfStaking() external pure returns (uint256) {
        return PRICE_OF_STAKING;
    }

    /**
     * @notice Calculates when a user can perform full unstaking (withdraw all tokens)
     * @dev Full unstaking requires waiting 21 days after the last time their balance reached 0
     * @param _account Address to check the unlock time for
     * @return Timestamp when full unstaking will be allowed
     */
    function getTimeToUserUnlockFullUnstakingTime(
        address _account
    ) public view returns (uint256) {
        for (uint256 i = userHistory[_account].length; i > 0; i--) {
            if (userHistory[_account][i - 1].totalStaked == 0) {
                return
                    userHistory[_account][i - 1].timestamp +
                    secondsToUnllockFullUnstaking.current;
            }
        }

        return
            userHistory[_account][0].timestamp +
            secondsToUnllockFullUnstaking.current;
    }

    /**
     * @notice Returns the timestamp after which the user may stake again (0 if already allowed).
     */
    function getTimeToUserUnlockStakingTime(
        address _account
    ) public view returns (uint256) {
        uint256 lengthOfHistory = userHistory[_account].length;

        if (lengthOfHistory == 0) {
            return 0;
        }
        if (userHistory[_account][lengthOfHistory - 1].totalStaked == 0) {
            return
                userHistory[_account][lengthOfHistory - 1].timestamp +
                secondsToUnlockStaking.current;
        } else {
            return 0;
        }
    }

    /**
     * @notice Returns the current full-unstake time-lock duration in seconds.
     */
    function getSecondsToUnlockFullUnstaking() external view returns (uint256) {
        return secondsToUnllockFullUnstaking.current;
    }

    /**
     * @notice Returns the current re-stake delay in seconds.
     */
    function getSecondsToUnlockStaking() external view returns (uint256) {
        return secondsToUnlockStaking.current;
    }

    /**
     * @notice Returns the current amount of staking tokens staked by a user
     * @dev Returns the total staked amount from the user's most recent transaction
     * @param _account Address to check the staked amount for
     * @return Amount of staking tokens currently staked by the user
     */
    function getUserAmountStaked(
        address _account
    ) public view returns (uint256) {
        uint256 lengthOfHistory = userHistory[_account].length;

        if (lengthOfHistory == 0) {
            return 0;
        }

        return userHistory[_account][lengthOfHistory - 1].totalStaked;
    }

    /**
     * @notice Returns the current Golden Fisher address.
     */
    function getGoldenFisher() external view returns (address) {
        return goldenFisher.current;
    }

    /**
     * @notice Returns the proposed Golden Fisher address (address(0) if none pending).
     */
    function getGoldenFisherProposal() external view returns (address) {
        return goldenFisher.proposal;
    }

    /**
     * @notice Returns the presale allowlist status and staked amount for an address.
     */
    function getPresaleStaker(
        address _account
    ) external view returns (bool, uint256) {
        return (
            userPresaleStaker[_account].isAllow,
            userPresaleStaker[_account].stakingAmount
        );
    }

    /**
     * @notice Returns the current Estimator contract address.
     */
    function getEstimatorAddress() external view returns (address) {
        return estimatorAddress.current;
    }

    /**
     * @notice Returns the proposed Estimator contract address (address(0) if none pending).
     */
    function getEstimatorProposal() external view returns (address) {
        return estimatorAddress.proposal;
    }

    /**
     * @notice Returns the current number of registered presale stakers
     * @dev Maximum allowed is 800 presale stakers
     * @return Current count of presale stakers
     */
    function getPresaleStakerCount() external view returns (uint256) {
        return presaleStakerCount;
    }

    /**
     * @notice Returns the public staking flag and pending proposal details.
     */
    function getAllowPublicStaking()
        external
        view
        returns (ProposalStructs.BoolTypeProposal memory)
    {
        return allowPublicStaking;
    }

    /**
     * @notice Returns the presale staking flag and pending proposal details.
     */
    function getAllowPresaleStaking()
        external
        view
        returns (ProposalStructs.BoolTypeProposal memory)
    {
        return allowPresaleStaking;
    }

    /**
     * @notice Returns the EvvmID of the integrated Core instance.
     */
    function getEvvmID() external view returns (uint256) {
        return core.getEvvmID();
    }

    /**
     * @notice Returns the address of the Core contract.
     */
    function getCoreAddress() external view returns (address) {
        return EVVM_ADDRESS;
    }

    function getIfUsedAsyncNonce(
        address user,
        uint256 nonce
    ) external view returns (bool) {
        return core.getIfUsedAsyncNonce(user, nonce);
    }

    /**
     * @notice Returns the address representing the Principal Token
     * @dev This is a constant address used to represent the principal token
     * @return Address representing the Principal Token (0x...0001)
     */
    function getMateAddress() external view returns (address) {
        return core.getPrincipalTokenAddress();
    }

    /**
     * @notice Returns the current admin/owner address
     * @dev The admin has full control over contract parameters and governance
     * @return Address of the current contract admin
     */
    function getOwner() external view returns (address) {
        return admin.current;
    }
}
