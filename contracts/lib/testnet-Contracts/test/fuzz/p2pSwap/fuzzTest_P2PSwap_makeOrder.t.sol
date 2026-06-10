// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

/** 
 _______ __   __ _______ _______   _______ _______ _______ _______ 
|       |  | |  |       |       | |       |       |       |       |
|    ___|  | |  |____   |____   | |_     _|    ___|  _____|_     _|
|   |___|  |_|  |____|  |____|  |   |   | |   |___| |_____  |   |  
|    ___|       | ______| ______|   |   | |    ___|_____  | |   |  
|   |   |       | |_____| |_____    |   | |   |___ _____| | |   |  
|___|   |_______|_______|_______|   |___| |_______|_______| |___|  
 */

pragma solidity ^0.8.0;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {Constants} from "test/Constants.sol";

import {Staking} from "@evvm/testnet-contracts/contracts/staking/Staking.sol";
import {
    NameService
} from "@evvm/testnet-contracts/contracts/nameService/NameService.sol";
import {Core} from "@evvm/testnet-contracts/contracts/core/Core.sol";
import {
    Erc191TestBuilder
} from "@evvm/testnet-contracts/library/Erc191TestBuilder.sol";
import {
    Estimator
} from "@evvm/testnet-contracts/contracts/staking/Estimator.sol";
import {
    CoreStorage
} from "@evvm/testnet-contracts/contracts/core/lib/CoreStorage.sol";
import {
    AdvancedStrings
} from "@evvm/testnet-contracts/library/utils/AdvancedStrings.sol";
import {
    CoreStructs
} from "@evvm/testnet-contracts/library/structs/CoreStructs.sol";
import {
    Treasury
} from "@evvm/testnet-contracts/contracts/treasury/Treasury.sol";
import {P2PSwap} from "@evvm/testnet-contracts/contracts/p2pSwap/P2PSwap.sol";
import {
    P2PSwapStructs
} from "@evvm/testnet-contracts/library/structs/P2PSwapStructs.sol";

contract fuzzTest_P2PSwap_makeOrder is Test, Constants {
    AccountData COMMON_USER_NO_STAKER_3 = WILDCARD_USER;

    function addBalance(address user, address token, uint256 amount) private {
        core.addBalance(user, token, amount);
    }

    struct MakeOrderFuzzTestInput {
        bool hasPriorityFee;
        uint16 amountA;
        uint16 amountB;
        uint16 priorityFee;
        uint16 noncePay;
        uint16 nonceP2PSwap;
        bool tokenScenario;
    }

    function _createSignatures(
        MakeOrderFuzzTestInput memory input,
        address tokenA,
        address tokenB,
        uint256 priorityFee,
        uint256 noncePay
    ) internal view returns (bytes memory signatureP2P, bytes memory signaturePay) {
        // swap signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            COMMON_USER_NO_STAKER_1.PrivateKey,
            Erc191TestBuilder.buildMessageSignedForMakeOrder(
                core.getEvvmID(),
                address(0),
                address(0),
                input.nonceP2PSwap,
                tokenA,
                tokenB,
                input.amountA,
                input.amountB
            )
        );
        signatureP2P = Erc191TestBuilder.buildERC191Signature(v, r, s);

        // pay signature
        (v, r, s) = vm.sign(
            COMMON_USER_NO_STAKER_1.PrivateKey,
            Erc191TestBuilder.buildMessageSignedForPay(
                core.getEvvmID(),
                address(p2pSwap),
                "",
                tokenA,
                input.amountA,
                priorityFee,
                address(p2pSwap),
                address(0),
                noncePay,
                true
            )
        );
        signaturePay = Erc191TestBuilder.buildERC191Signature(v, r, s);
    }

    function _verifyBalances(
        MakeOrderFuzzTestInput memory input,
        address tokenA,
        address tokenB,
        uint256 priorityFee,
        uint256 rewardAmountMateToken,
        uint256 initialContractBalance
    ) internal {
        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, tokenA),
            0 ether
        );
        
        if (tokenA == PRINCIPAL_TOKEN_ADDRESS) {
            assertEq(
                core.getBalance(address(p2pSwap), tokenA),
                input.amountA + initialContractBalance
            );
        } else {
            assertEq(core.getBalance(address(p2pSwap), tokenA), input.amountA);
        }

        if (input.hasPriorityFee) {
            if (tokenA == PRINCIPAL_TOKEN_ADDRESS) {
                assertEq(
                    core.getBalance(COMMON_USER_STAKER.Address, tokenA),
                    priorityFee + rewardAmountMateToken
                );
            } else {
                assertEq(
                    core.getBalance(COMMON_USER_STAKER.Address, tokenA),
                    priorityFee
                );
                assertEq(
                    core.getBalance(COMMON_USER_STAKER.Address, tokenB),
                    rewardAmountMateToken
                );
            }
        }
    }

    function test__fuzz__makeOrder(
        MakeOrderFuzzTestInput memory input
    ) external {
        // assumptions
        vm.assume(input.priorityFee > 0);
        vm.assume(input.amountA > 0 && input.amountB > 0);
        vm.assume(input.noncePay != input.nonceP2PSwap);

        // Form inputs
        address tokenA = input.tokenScenario ? ETHER_ADDRESS : PRINCIPAL_TOKEN_ADDRESS;
        address tokenB = input.tokenScenario ? PRINCIPAL_TOKEN_ADDRESS : ETHER_ADDRESS;
        uint256 priorityFee = input.hasPriorityFee ? input.priorityFee : 0;
        uint256 rewardAmountMateToken = priorityFee > 0
            ? (core.getRewardAmount() * 3)
            : (core.getRewardAmount() * 2);
        uint256 initialContractBalance = 50000000000000000000;

        // fund accounts
        addBalance(COMMON_USER_NO_STAKER_1.Address, tokenA, input.amountA + priorityFee);
        addBalance(address(p2pSwap), PRINCIPAL_TOKEN_ADDRESS, initialContractBalance);

        // create signatures
        (bytes memory signatureP2P, bytes memory signaturePay) = 
            _createSignatures(input, tokenA, tokenB, priorityFee, input.noncePay);

        // execute tx
        vm.startPrank(COMMON_USER_STAKER.Address);
        (uint256 market, ) = p2pSwap.makeOrder(
            COMMON_USER_NO_STAKER_1.Address,
            tokenA,
            tokenB,
            input.amountA,
            input.amountB,
            address(0),
            address(0),
            input.nonceP2PSwap,
            signatureP2P,
            priorityFee,
            input.noncePay,
            signaturePay
        );
        vm.stopPrank();

        // verify market state
        P2PSwapStructs.MarketInformation memory marketInfo = p2pSwap.getMarketMetadata(market);
        assertEq(marketInfo.tokenA, tokenA);
        assertEq(marketInfo.tokenB, tokenB);
        assertEq(marketInfo.maxSlot, 1);
        assertEq(marketInfo.ordersAvailable, 1);

        // verify balances
        _verifyBalances(input, tokenA, tokenB, priorityFee, rewardAmountMateToken, initialContractBalance);
    }
}
