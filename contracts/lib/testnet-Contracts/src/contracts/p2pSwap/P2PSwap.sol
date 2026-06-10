// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.org/docs/EVVMNoncommercialLicense

pragma solidity ^0.8.0;

import {
    P2PSwapHashUtils as Hash
} from "@evvm/testnet-contracts/library/utils/signature/P2PSwapHashUtils.sol";
import {
    P2PSwapStructs as Structs
} from "@evvm/testnet-contracts/library/structs/P2PSwapStructs.sol";

import {EvvmService} from "@evvm/testnet-contracts/library/EvvmService.sol";
import {CoreStructs} from "@evvm/testnet-contracts/interfaces/ICore.sol";

import {
    ProposalStructs
} from "@evvm/testnet-contracts/library/utils/governance/ProposalStructs.sol";

/**
 /$$$$$$$  /$$$$$$ /$$$$$$$  /$$$$$$                                
| $$__  $$/$$__  $| $$__  $$/$$__  $$                               
| $$  \ $|__/  \ $| $$  \ $| $$  \__//$$  /$$  /$$ /$$$$$$  /$$$$$$ 
| $$$$$$$/ /$$$$$$| $$$$$$$|  $$$$$$| $$ | $$ | $$|____  $$/$$__  $$
| $$____/ /$$____/| $$____/ \____  $| $$ | $$ | $$ /$$$$$$| $$  \ $$
| $$     | $$     | $$      /$$  \ $| $$ | $$ | $$/$$__  $| $$  | $$
| $$     | $$$$$$$| $$     |  $$$$$$|  $$$$$/$$$$|  $$$$$$| $$$$$$$/
|__/     |________|__/      \______/ \_____/\___/ \_______| $$____/ 
                                                          | $$      
                                                          | $$      
                                                          |__/      

 * @title EVVM P2P Swap
 * @author Mate labs  
 * @notice Peer-to-peer decentralized exchange for token trading within EVVM.
 * @dev Supports order book-style trading with customizable fee models. 
 *      Integrates with Core.sol for asset locking and settlements, and Staking.sol for validator rewards.
 */

contract P2PSwap is EvvmService {
    /// @notice Current contract owner.
    address owner;
    /// @notice Proposed new owner pending acceptance.
    address owner_proposal;
    /// @notice Deadline for accepting the owner proposal.
    uint256 owner_timeToAccept;

    /// @notice Fee split percentages for order fills (seller/service/staker).
    Structs.Percentage rewardPercentage;
    /// @notice Pending proposal for new fee split percentages.
    Structs.Percentage rewardPercentage_proposal;
    /// @notice Deadline for accepting the reward percentage proposal.
    uint256 rewardPercentage_timeToAcceptNewChange;

    /// @notice Proportional fee applied to fills in basis points (500 = 5%).
    ProposalStructs.UintTypeProposal percentageFee;

    /// @notice Maximum cap for fixed-fee fills.
    ProposalStructs.UintTypeProposal maxLimitFillFixedFee;

    /// @notice Token pending admin withdrawal.
    address tokenToWithdraw;
    /// @notice Amount pending admin withdrawal.
    uint256 amountToWithdraw;
    /// @notice Recipient of the pending withdrawal.
    address recipientToWithdraw;
    /// @notice Deadline for executing the withdrawal.
    uint256 timeToWithdrawal;

    /// @notice Total number of markets created.
    uint256 marketCount;

    /// @notice Maps a token pair to its market ID.
    mapping(address tokenA => mapping(address tokenB => uint256 id)) marketId;

    /// @notice Stores metadata for each market.
    mapping(uint256 id => Structs.MarketInformation info) marketMetadata;

    /// @notice Stores orders within each market indexed by slot.
    mapping(uint256 idMarket => mapping(uint256 idOrder => Structs.Order)) ordersInsideMarket;

    /// @notice Accumulated service fees per token.
    mapping(address => uint256) balancesOfContract;

    /**
     * @notice Initializes P2PSwap with Core, Staking, and owner addresses.
     * @param _coreAddress Core contract address.
     * @param _stakingAddress Staking contract address.
     * @param _owner Initial owner address.
     */
    constructor(
        address _coreAddress,
        address _stakingAddress,
        address _owner
    ) EvvmService(_coreAddress, _stakingAddress) {
        owner = _owner;
        maxLimitFillFixedFee.current = 0.001 ether;
        percentageFee.current = 500;
        rewardPercentage = Structs.Percentage({
            seller: 5000,
            service: 4000,
            mateStaker: 1000
        });
    }

    /**
     * @notice Creates a new limit order in a specific trading market.
     * @dev Locks tokenA in Core.sol and opens an order slot.
     *      Markets are automatically created for new token pairs.
     * @param user Seller address.
     * @param tokenA Address of the token being sold.
     * @param tokenB Address of the token being bought.
     * @param amountA Amount of tokenA offered.
     * @param amountB Amount of tokenB requested.
     * @param senderExecutor Address of the calling service (must match msg.sender).
     * @param originExecutor Origin address for signature validation.
     * @param nonce Async nonce for this operation.
     * @param signature Seller's authorization signature.
     * @param priorityFeePay Optional priority fee for the executor.
     * @param noncePay Nonce for the Core payment (locks tokenA).
     * @param signaturePay Signature for the Core payment.
     * @return market The ID of the market.
     * @return orderId The ID of the order within that market.
     */
    function makeOrder(
        address user,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay
    ) external returns (uint256 market, uint256 orderId) {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForMakeOrder(tokenA, tokenB, amountA, amountB),
            originExecutor,
            nonce,
            true,
            signature
        );

        requestPay(
            user,
            tokenA,
            amountA,
            priorityFeePay,
            originExecutor,
            noncePay,
            true,
            signaturePay
        );

        market = findMarket(tokenA, tokenB);
        if (market == 0) {
            market = createMarket(tokenA, tokenB);
        }

        if (
            marketMetadata[market].maxSlot ==
            marketMetadata[market].ordersAvailable
        ) {
            marketMetadata[market].maxSlot++;
            marketMetadata[market].ordersAvailable++;
            orderId = marketMetadata[market].maxSlot;
        } else {
            for (uint256 i = 1; i <= marketMetadata[market].maxSlot + 1; i++) {
                if (ordersInsideMarket[market][i].seller == address(0)) {
                    orderId = i;
                    break;
                }
            }
            marketMetadata[market].ordersAvailable++;
        }

        ordersInsideMarket[market][orderId] = Structs.Order(
            user,
            amountA,
            amountB
        );

        if (core.isAddressStaker(msg.sender)) {
            if (priorityFeePay > 0) {
                // send the executor the priorityFee
                makeCaPay(msg.sender, tokenA, priorityFeePay);
            }
        }

        // send some mate token reward to the executor (independent of the priorityFee the user attached)
        _rewardExecutor(msg.sender, priorityFeePay > 0 ? 3 : 2);
    }

    /**
     * @notice Cancels an existing order and refunds locked tokenA to the seller.
     * @dev Only the order owner can cancel. The market slot is recycled for new orders.
     * @param user Order owner address.
     * @param tokenA Token being sold.
     * @param tokenB Token being bought.
     * @param orderId Order slot to cancel.
     * @param senderExecutor Address of the calling service (must match msg.sender).
     * @param originExecutor Origin address for signature validation.
     * @param nonce Async nonce for this operation.
     * @param signature Cancellation authorization signature.
     * @param priorityFeePay Optional priority fee for the executor.
     * @param noncePay Nonce for the priority fee payment.
     * @param signaturePay Signature for the priority fee payment.
     */
    function cancelOrder(
        address user,
        address tokenA,
        address tokenB,
        uint256 orderId,
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
            Hash.hashDataForCancelOrder(tokenA, tokenB, orderId),
            originExecutor,
            nonce,
            true,
            signature
        );

        uint256 market = findMarket(tokenA, tokenB);

        _validateOrderOwnership(market, orderId, user);

        if (priorityFeePay > 0) {
            requestPay(
                user,
                core.getPrincipalTokenAddress(),
                0,
                priorityFeePay,
                originExecutor,
                noncePay,
                true,
                signaturePay
            );
        }

        makeCaPay(user, tokenA, ordersInsideMarket[market][orderId].amountA);

        _clearOrderAndUpdateMarket(market, orderId);

        if (core.isAddressStaker(msg.sender) && priorityFeePay > 0) {
            makeCaPay(
                msg.sender,
                core.getPrincipalTokenAddress(),
                priorityFeePay
            );
        }
        _rewardExecutor(msg.sender, priorityFeePay > 0 ? 3 : 2);
    }

    /**
     * @notice Fills an order using a proportional fee (fee = amountB * percentageFee / 10,000).
     * @dev Overpayment above amountB + fee is automatically refunded to the buyer.
     * @param user Buyer address filling the order.
     * @param tokenA Token being bought by the filler.
     * @param tokenB Token being sold by the filler.
     * @param orderId Order slot to fill.
     * @param amountOfTokenBToFill Amount of tokenB to pay (must cover order amount + fee).
     * @param senderExecutor Address of the calling service (must match msg.sender).
     * @param originExecutor Origin address for signature validation.
     * @param nonce Async nonce for this operation.
     * @param signature Fill authorization signature.
     * @param priorityFeePay Optional priority fee for the executor.
     * @param noncePay Nonce for the payment.
     * @param signaturePay Signature for the payment.
     */
    function dispatchOrder_fillPropotionalFee(
        address user,
        address tokenA,
        address tokenB,
        uint256 orderId,
        uint256 amountOfTokenBToFill,
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
            Hash.hashDataForDispatchOrder(tokenA, tokenB, orderId),
            originExecutor,
            nonce,
            true,
            signature
        );

        uint256 market = findMarket(tokenA, tokenB);

        Structs.Order storage order = _validateMarketAndOrder(market, orderId);

        uint256 fee = calculateFillPropotionalFee(order.amountB);
        uint256 requiredAmount = order.amountB + fee;

        if (amountOfTokenBToFill < requiredAmount) {
            revert("Insuficient amountOfTokenToFill");
        }

        requestPay(
            user,
            tokenB,
            amountOfTokenBToFill,
            priorityFeePay,
            originExecutor,
            noncePay,
            true,
            signaturePay
        );

        // si es mas del fee + el monto de la orden hacemos caPay al usuario del sobranate
        bool didRefund = _handleOverpaymentRefund(
            user,
            tokenB,
            amountOfTokenBToFill,
            requiredAmount
        );

        // distribute payments to seller and executor
        _distributePayments(
            tokenB,
            order.amountB,
            fee,
            order.seller,
            msg.sender,
            priorityFeePay
        );

        // pay user with token A
        makeCaPay(user, tokenA, order.amountA);

        _rewardExecutor(msg.sender, didRefund ? 5 : 4);

        _clearOrderAndUpdateMarket(market, orderId);
    }

    /**
     * @notice Fills an order using a capped fixed fee (min of proportional fee and maxLimitFillFixedFee).
     * @dev Accepts payment within a 10% tolerance window below the full fee. Final fee is derived from actual payment.
     * @param user Buyer address filling the order.
     * @param tokenA Token being bought by the filler.
     * @param tokenB Token being sold by the filler.
     * @param orderId Order slot to fill.
     * @param amountOfTokenBToFill Amount of tokenB to pay.
     * @param senderExecutor Address of the calling service (must match msg.sender).
     * @param originExecutor Origin address for signature validation.
     * @param nonce Async nonce for this operation.
     * @param signature Fill authorization signature.
     * @param priorityFeePay Optional priority fee for the executor.
     * @param noncePay Nonce for the payment.
     * @param signaturePay Signature for the payment.
     * @param maxFillFixedFee Fee cap override (for testing).
     */
    function dispatchOrder_fillFixedFee(
        address user,
        address tokenA,
        address tokenB,
        uint256 orderId,
        uint256 amountOfTokenBToFill,
        address senderExecutor,
        address originExecutor,
        uint256 nonce,
        bytes calldata signature,
        uint256 priorityFeePay,
        uint256 noncePay,
        bytes calldata signaturePay,
        uint256 maxFillFixedFee ///@dev for testing purposes
    ) external {
        core.validateAndConsumeNonce(
            user,
            senderExecutor,
            Hash.hashDataForDispatchOrder(tokenA, tokenB, orderId),
            originExecutor,
            nonce,
            true,
            signature
        );

        uint256 market = findMarket(tokenA, tokenB);

        Structs.Order storage order = _validateMarketAndOrder(market, orderId);

        (uint256 fee, uint256 fee10) = calculateFillFixedFee(
            order.amountB,
            maxFillFixedFee
        );

        uint256 minRequired = order.amountB + fee - fee10;
        uint256 fullRequired = order.amountB + fee;

        if (amountOfTokenBToFill < minRequired) {
            revert("Insuficient amountOfTokenBToFill");
        }

        requestPay(
            user,
            tokenB,
            amountOfTokenBToFill,
            priorityFeePay,
            originExecutor,
            noncePay,
            true,
            signaturePay
        );

        uint256 finalFee = _calculateFinalFee(
            amountOfTokenBToFill,
            order.amountB,
            fee,
            fee10
        );

        // si es mas del fee + el monto de la orden hacemos caPay al usuario del sobranate
        bool didRefund = _handleOverpaymentRefund(
            user,
            tokenB,
            amountOfTokenBToFill,
            fullRequired
        );

        // distribute payments to seller and executor
        _distributePayments(
            tokenB,
            order.amountB,
            finalFee,
            order.seller,
            msg.sender,
            priorityFeePay
        );

        makeCaPay(user, tokenA, order.amountA);

        _rewardExecutor(msg.sender, didRefund ? 5 : 4);

        _clearOrderAndUpdateMarket(market, orderId);
    }

    /**
     * @dev Computes proportional fill fee as a percentage of the order amount.
     * @param amount Order tokenB amount.
     * @return fee Fee in tokenB units.
     */
    function calculateFillPropotionalFee(
        uint256 amount
    ) internal view returns (uint256 fee) {
        ///@dev get the % of the amount
        fee = (amount * percentageFee.current) / 10_000;
    }

    /**
     * @dev Computes the capped fixed fee and its 10% tolerance window.
     * @param amount Order tokenB amount.
     * @param maxFillFixedFee Absolute fee cap.
     * @return fee Capped fee amount.
     * @return fee10 10% of the fee (tolerance window).
     */
    function calculateFillFixedFee(
        uint256 amount,
        uint256 maxFillFixedFee
    ) internal view returns (uint256 fee, uint256 fee10) {
        if (calculateFillPropotionalFee(amount) > maxFillFixedFee) {
            fee = maxFillFixedFee;
            fee10 = (fee * 1000) / 10_000;
        } else {
            fee = calculateFillPropotionalFee(amount);
        }
    }

    /**
     * @dev Calculates the final fee for fixed fee dispatch considering tolerance range
     * @param amountPaid Amount paid by user
     * @param orderAmount Base order amount
     * @param fee Full fee amount
     * @param fee10 10% tolerance of fee
     * @return finalFee The calculated final fee
     */
    function _calculateFinalFee(
        uint256 amountPaid,
        uint256 orderAmount,
        uint256 fee,
        uint256 fee10
    ) internal pure returns (uint256 finalFee) {
        uint256 minRequired = orderAmount + fee - fee10;
        uint256 fullRequired = orderAmount + fee;

        if (amountPaid >= minRequired && amountPaid < fullRequired) {
            finalFee = amountPaid - orderAmount;
        } else {
            finalFee = fee;
        }
    }

    //◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢
    // Internal helper functions to avoid Stack too deep
    //◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢

    /**
     * @dev Validates that a market and order exist and are valid
     * @param market The market ID
     * @param orderId The order ID within the market
     * @return order The order data if valid
     */
    function _validateMarketAndOrder(
        uint256 market,
        uint256 orderId
    ) internal view returns (Structs.Order storage order) {
        if (market == 0) {
            revert("Invalid order");
        }
        order = ordersInsideMarket[market][orderId];
        if (order.seller == address(0)) {
            revert("Invalid order");
        }
    }

    /**
     * @dev Validates that a market exists and the user is the seller of the order
     * @param market The market ID
     * @param orderId The order ID
     * @param user The expected seller address
     */
    function _validateOrderOwnership(
        uint256 market,
        uint256 orderId,
        address user
    ) internal view {
        if (market == 0 || ordersInsideMarket[market][orderId].seller != user) {
            revert("Invalid order");
        }
    }

    /**
     * @dev Rewards the executor (staker) with MATE tokens based on operation complexity
     * @param executor The address of the executor
     * @param multiplier The reward multiplier (2, 3, 4, or 5)
     */
    function _rewardExecutor(address executor, uint256 multiplier) internal {
        if (core.isAddressStaker(executor)) {
            makeCaPay(
                executor,
                core.getPrincipalTokenAddress(),
                core.getRewardAmount() * multiplier
            );
        }
    }

    /**
     * @dev Clears an order and updates market metadata
     * @param market The market ID
     * @param orderId The order ID to clear
     */
    function _clearOrderAndUpdateMarket(
        uint256 market,
        uint256 orderId
    ) internal {
        ordersInsideMarket[market][orderId].seller = address(0);
        marketMetadata[market].ordersAvailable--;
    }

    /**
     * @dev Handles refund to user if they overpaid
     * @param user The user address to refund
     * @param token The token address
     * @param amountPaid The amount the user paid
     * @param amountRequired The required amount (order amount + fee)
     * @return didRefund Whether a refund was made
     */
    function _handleOverpaymentRefund(
        address user,
        address token,
        uint256 amountPaid,
        uint256 amountRequired
    ) internal returns (bool didRefund) {
        if (amountPaid > amountRequired) {
            makeCaPay(user, token, amountPaid - amountRequired);
            return true;
        }
        return false;
    }

    /**
     * @dev Distributes payment to seller and executor, and accumulates service fee
     * @param token The token address for payment
     * @param orderAmount The base order amount
     * @param fee The fee amount to distribute
     * @param seller The seller address
     * @param executor The executor address
     * @param priorityFee The priority fee for executor
     */
    function _distributePayments(
        address token,
        uint256 orderAmount,
        uint256 fee,
        address seller,
        address executor,
        uint256 priorityFee
    ) internal {
        uint256 sellerAmount = orderAmount +
            ((fee * rewardPercentage.seller) / 10_000);
        uint256 executorAmount = priorityFee +
            ((fee * rewardPercentage.mateStaker) / 10_000);

        CoreStructs.DisperseCaPayMetadata[]
            memory toData = new CoreStructs.DisperseCaPayMetadata[](2);

        toData[0] = CoreStructs.DisperseCaPayMetadata(sellerAmount, seller);
        toData[1] = CoreStructs.DisperseCaPayMetadata(executorAmount, executor);

        balancesOfContract[token] += (fee * rewardPercentage.service) / 10_000;

        makeDisperseCaPay(toData, token, sellerAmount + executorAmount);
    }

    /**
     * @dev Registers a new market for a token pair.
     * @param tokenA Token A address.
     * @param tokenB Token B address.
     * @return New market ID.
     */
    function createMarket(
        address tokenA,
        address tokenB
    ) internal returns (uint256) {
        marketCount++;
        marketId[tokenA][tokenB] = marketCount;
        marketMetadata[marketCount] = Structs.MarketInformation(
            tokenA,
            tokenB,
            0,
            0
        );
        return marketCount;
    }

    //◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢
    // Admin tools
    //◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢

    /**
     * @notice Proposes a new owner with a 1-day acceptance window.
     * @param _owner Proposed owner address.
     */
    function proposeOwner(address _owner) external {
        if (msg.sender != owner) {
            revert();
        }
        owner_proposal = _owner;
        owner_timeToAccept = block.timestamp + 1 days;
    }

    /// @notice Cancels the pending owner proposal.
    function rejectProposeOwner() external {
        if (
            msg.sender != owner_proposal || block.timestamp > owner_timeToAccept
        ) {
            revert();
        }
        owner_proposal = address(0);
    }

    /// @notice Accepts the pending owner proposal, transferring ownership.
    function acceptOwner() external {
        if (
            msg.sender != owner_proposal || block.timestamp > owner_timeToAccept
        ) {
            revert();
        }
        owner = owner_proposal;
        owner_proposal = address(0);
    }

    /**
     * @notice Proposes new reward split percentages for fixed-fee fills.
     * @param _seller Seller share in basis points.
     * @param _service Service share in basis points.
     * @param _mateStaker Staker share in basis points.
     */
    function proposeFillFixedPercentage(
        uint256 _seller,
        uint256 _service,
        uint256 _mateStaker
    ) external {
        if (msg.sender != owner) {
            revert();
        }
        if (_seller + _service + _mateStaker != 10_000) {
            revert();
        }
        rewardPercentage_proposal = Structs.Percentage(
            _seller,
            _service,
            _mateStaker
        );
        rewardPercentage_timeToAcceptNewChange = block.timestamp + 1 days;
    }

    /// @notice Cancels the pending fixed-fee reward percentage proposal.
    function rejectProposeFillFixedPercentage() external {
        if (
            msg.sender != owner ||
            block.timestamp > rewardPercentage_timeToAcceptNewChange
        ) {
            revert();
        }
        rewardPercentage_proposal = Structs.Percentage(0, 0, 0);
    }

    /// @notice Applies the pending fixed-fee reward percentage proposal.
    function acceptFillFixedPercentage() external {
        if (
            msg.sender != owner ||
            block.timestamp > rewardPercentage_timeToAcceptNewChange
        ) {
            revert();
        }
        rewardPercentage = rewardPercentage_proposal;
    }

    /**
     * @notice Proposes new reward split percentages for proportional-fee fills.
     * @param _seller Seller share in basis points.
     * @param _service Service share in basis points.
     * @param _mateStaker Staker share in basis points.
     */
    function proposeFillPropotionalPercentage(
        uint256 _seller,
        uint256 _service,
        uint256 _mateStaker
    ) external {
        if (msg.sender != owner || _seller + _service + _mateStaker != 10_000) {
            revert();
        }
        rewardPercentage_proposal = Structs.Percentage(
            _seller,
            _service,
            _mateStaker
        );
        rewardPercentage_timeToAcceptNewChange = block.timestamp + 1 days;
    }

    /// @notice Cancels the pending proportional-fee reward percentage proposal.
    function rejectProposeFillPropotionalPercentage() external {
        if (
            msg.sender != owner ||
            block.timestamp > rewardPercentage_timeToAcceptNewChange
        ) {
            revert();
        }
        rewardPercentage_proposal = Structs.Percentage(0, 0, 0);
    }

    /// @notice Applies the pending proportional-fee reward percentage proposal.
    function acceptFillPropotionalPercentage() external {
        if (
            msg.sender != owner ||
            block.timestamp > rewardPercentage_timeToAcceptNewChange
        ) {
            revert();
        }
        rewardPercentage = rewardPercentage_proposal;
    }

    /**
     * @notice Proposes a new proportional fee percentage.
     * @param _percentageFee New fee in basis points (e.g. 500 = 5%).
     */
    function proposePercentageFee(uint256 _percentageFee) external {
        if (msg.sender != owner) {
            revert();
        }
        percentageFee.proposal = _percentageFee;
        percentageFee.timeToAccept = block.timestamp + 1 days;
    }

    /// @notice Cancels the pending percentage fee proposal.
    function rejectProposePercentageFee() external {
        if (
            msg.sender != owner || block.timestamp > percentageFee.timeToAccept
        ) {
            revert();
        }
        percentageFee.proposal = 0;
    }

    /// @notice Applies the pending percentage fee proposal.
    function acceptPercentageFee() external {
        if (
            msg.sender != owner || block.timestamp > percentageFee.timeToAccept
        ) {
            revert();
        }
        percentageFee.current = percentageFee.proposal;
    }

    /**
     * @notice Proposes a new maximum fixed fee cap.
     * @param _maxLimitFillFixedFee New cap amount.
     */
    function proposeMaxLimitFillFixedFee(
        uint256 _maxLimitFillFixedFee
    ) external {
        if (msg.sender != owner) {
            revert();
        }
        maxLimitFillFixedFee.proposal = _maxLimitFillFixedFee;
        maxLimitFillFixedFee.timeToAccept = block.timestamp + 1 days;
    }

    /// @notice Cancels the pending max fixed fee proposal.
    function rejectProposeMaxLimitFillFixedFee() external {
        if (
            msg.sender != owner ||
            block.timestamp > maxLimitFillFixedFee.timeToAccept
        ) {
            revert();
        }
        maxLimitFillFixedFee.proposal = 0;
    }

    /// @notice Applies the pending max fixed fee proposal.
    function acceptMaxLimitFillFixedFee() external {
        if (
            msg.sender != owner ||
            block.timestamp > maxLimitFillFixedFee.timeToAccept
        ) {
            revert();
        }
        maxLimitFillFixedFee.current = maxLimitFillFixedFee.proposal;
    }

    /**
     * @notice Proposes a fee withdrawal with a 1-day timelock.
     * @param _tokenToWithdraw Token address to withdraw.
     * @param _amountToWithdraw Amount to withdraw.
     * @param _to Recipient address.
     */
    function proposeWithdrawal(
        address _tokenToWithdraw,
        uint256 _amountToWithdraw,
        address _to
    ) external {
        if (
            msg.sender != owner ||
            _amountToWithdraw > balancesOfContract[_tokenToWithdraw]
        ) {
            revert();
        }
        tokenToWithdraw = _tokenToWithdraw;
        amountToWithdraw = _amountToWithdraw;
        recipientToWithdraw = _to;
        timeToWithdrawal = block.timestamp + 1 days;
    }

    /// @notice Cancels the pending withdrawal proposal.
    function rejectProposeWithdrawal() external {
        if (msg.sender != owner || block.timestamp > timeToWithdrawal) {
            revert();
        }
        tokenToWithdraw = address(0);
        amountToWithdraw = 0;
        recipientToWithdraw = address(0);
        timeToWithdrawal = 0;
    }

    /// @notice Executes the pending withdrawal after the timelock.
    function acceptWithdrawal() external {
        if (msg.sender != owner || block.timestamp > timeToWithdrawal) {
            revert();
        }
        makeCaPay(recipientToWithdraw, tokenToWithdraw, amountToWithdraw);
        balancesOfContract[tokenToWithdraw] -= amountToWithdraw;

        tokenToWithdraw = address(0);
        amountToWithdraw = 0;
        recipientToWithdraw = address(0);
        timeToWithdrawal = 0;
    }

    /**
     * @notice Stakes MATE tokens from the service balance.
     * @param amount Number of staking slots to purchase.
     */
    function stake(uint256 amount) external {
        if (
            msg.sender != owner ||
            amount * staking.priceOfStaking() >
            balancesOfContract[0x0000000000000000000000000000000000000001]
        ) revert();

        _makeStakeService(amount);
    }

    /**
     * @notice Unstakes MATE tokens back to the service balance.
     * @param amount Number of staking slots to release.
     */
    function unstake(uint256 amount) external {
        if (msg.sender != owner) revert();

        _makeUnstakeService(amount);
    }

    /**
     * @notice Manually records an added balance for a token (admin only, for accounting).
     * @param _token Token address.
     * @param _amount Amount to add.
     */
    function addBalance(address _token, uint256 _amount) external {
        if (msg.sender != owner) {
            revert();
        }
        balancesOfContract[_token] += _amount;
    }

    //◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢
    //getters
    //◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢◤◢
    /**
     * @notice Returns all active orders in a market.
     * @param market Market ID.
     * @return orders Array of orders with market and slot info.
     */
    function getAllMarketOrders(
        uint256 market
    ) public view returns (Structs.OrderForGetter[] memory orders) {
        orders = new Structs.OrderForGetter[](
            marketMetadata[market].maxSlot + 1
        );

        for (uint256 i = 1; i <= marketMetadata[market].maxSlot + 1; i++) {
            if (ordersInsideMarket[market][i].seller != address(0)) {
                orders[i - 1] = Structs.OrderForGetter(
                    market,
                    i,
                    ordersInsideMarket[market][i].seller,
                    ordersInsideMarket[market][i].amountA,
                    ordersInsideMarket[market][i].amountB
                );
            }
        }
        return orders;
    }

    /**
     * @notice Returns a single order by market and order ID.
     * @param market Market ID.
     * @param orderId Order slot index.
     * @return order Order data.
     */
    function getOrder(
        uint256 market,
        uint256 orderId
    ) public view returns (Structs.Order memory order) {
        order = ordersInsideMarket[market][orderId];
        return order;
    }

    /**
     * @notice Returns all orders placed by a user in a specific market.
     * @param user Seller address.
     * @param market Market ID.
     * @return orders Array of matching orders.
     */
    function getMyOrdersInSpecificMarket(
        address user,
        uint256 market
    ) public view returns (Structs.OrderForGetter[] memory orders) {
        orders = new Structs.OrderForGetter[](
            marketMetadata[market].maxSlot + 1
        );

        for (uint256 i = 1; i <= marketMetadata[market].maxSlot + 1; i++) {
            if (ordersInsideMarket[market][i].seller == user) {
                orders[i - 1] = Structs.OrderForGetter(
                    market,
                    i,
                    ordersInsideMarket[market][i].seller,
                    ordersInsideMarket[market][i].amountA,
                    ordersInsideMarket[market][i].amountB
                );
            }
        }
        return orders;
    }

    /**
     * @notice Returns the market ID for a token pair, or 0 if it doesn't exist.
     * @param tokenA Token A address.
     * @param tokenB Token B address.
     * @return Market ID.
     */
    function findMarket(
        address tokenA,
        address tokenB
    ) public view returns (uint256) {
        return marketId[tokenA][tokenB];
    }

    /**
     * @notice Returns metadata for a specific market.
     * @param market Market ID.
     * @return Market info struct.
     */
    function getMarketMetadata(
        uint256 market
    ) public view returns (Structs.MarketInformation memory) {
        return marketMetadata[market];
    }

    /**
     * @notice Returns metadata for all markets.
     * @return Array of all market info structs.
     */
    function getAllMarketsMetadata()
        public
        view
        returns (Structs.MarketInformation[] memory)
    {
        Structs.MarketInformation[]
            memory markets = new Structs.MarketInformation[](marketCount + 1);
        for (uint256 i = 1; i <= marketCount; i++) {
            markets[i - 1] = marketMetadata[i];
        }
        return markets;
    }

    /**
     * @notice Returns the accumulated service fee balance for a token.
     * @param token Token address.
     * @return Accumulated fee balance.
     */
    function getBalanceOfContract(
        address token
    ) external view returns (uint256) {
        return balancesOfContract[token];
    }

    /// @notice Returns the proposed new owner address.
    function getOwnerProposal() external view returns (address) {
        return owner_proposal;
    }

    /// @notice Returns the current owner address.
    function getOwner() external view returns (address) {
        return owner;
    }

    /// @notice Returns the deadline for accepting the owner proposal.
    function getOwnerTimeToAccept() external view returns (uint256) {
        return owner_timeToAccept;
    }

    /// @notice Returns the pending fee split percentage proposal.
    function getRewardPercentageProposal()
        external
        view
        returns (Structs.Percentage memory)
    {
        return rewardPercentage_proposal;
    }

    /// @notice Returns the current fee split percentages.
    function getRewardPercentage()
        external
        view
        returns (Structs.Percentage memory)
    {
        return rewardPercentage;
    }

    /// @notice Returns the proposed new percentage fee.
    function getProposalPercentageFee() external view returns (uint256) {
        return percentageFee.proposal;
    }

    /// @notice Returns the current percentage fee in basis points.
    function getPercentageFee() external view returns (uint256) {
        return percentageFee.current;
    }

    /// @notice Returns the proposed new max fixed fee cap.
    function getMaxLimitFillFixedFeeProposal() external view returns (uint256) {
        return maxLimitFillFixedFee.proposal;
    }

    /// @notice Returns the current max fixed fee cap.
    function getMaxLimitFillFixedFee() external view returns (uint256) {
        return maxLimitFillFixedFee.current;
    }

    /**
     * @notice Returns the details of the pending withdrawal proposal.
     * @return Token address, amount, recipient, and deadline.
     */
    function getProposedWithdrawal()
        external
        view
        returns (address, uint256, address, uint256)
    {
        return (
            tokenToWithdraw,
            amountToWithdraw,
            recipientToWithdraw,
            timeToWithdrawal
        );
    }
}
