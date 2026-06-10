// SPDX-License-Identifier: EVVM-NONCOMMERCIAL-1.0
// Full license terms available at: https://www.evvm.info/docs/EVVMNoncommercialLicense

/**
 ____ ___      .__  __      __                  __   
|    |   \____ |___/  |_  _/  |_  ____   ______/  |_ 
|    |   /    \|  \   __\ \   ___/ __ \ /  ___\   __\
|    |  |   |  |  ||  |    |  | \  ___/ \___ \ |  |  
|______/|___|  |__||__|    |__|  \___  /____  >|__|  
             \/                      \/     \/       
                                  __                 
_______  _______  __ ____________/  |_               
\_  __ _/ __ \  \/ _/ __ \_  __ \   __\              
 |  | \\  ___/\   /\  ___/|  | \/|  |                
 |__|   \___  >\_/  \___  |__|   |__|                
            \/          \/                                                                                 
 */
pragma solidity ^0.8.0;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "test/Constants.sol";
import "@evvm/testnet-contracts/library/Erc191TestBuilder.sol";

import {Core} from "@evvm/testnet-contracts/contracts/core/Core.sol";
import {CoreError} from "@evvm/testnet-contracts/library/errors/CoreError.sol";

contract unitTestRevert_Core_dispersePay is Test, Constants {
    AccountData COMMON_USER_NO_STAKER_3 = WILDCARD_USER;

    function executeBeforeSetUp() internal override {
        _executeFn_nameService_registrationUsername(
            COMMON_USER_NO_STAKER_2,
            "dummy",
            444,
            address(0),
            address(0),
            uint256(
                0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0
            ),
            address(0),
            address(0),
            uint256(
                0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1
            ),
            uint256(
                0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff2
            )
        );
        core.setPointStaker(COMMON_USER_STAKER.Address, 0x01);
    }

    function _addBalance(
        AccountData memory _user,
        address _token,
        uint256 _amount,
        uint256 _priorityFee
    ) private returns (uint256 amount, uint256 priorityFee) {
        core.addBalance(_user.Address, _token, _amount + _priorityFee);
        return (_amount, _priorityFee);
    }

    /**
     * Function to test: dispersePay
     * nS: No staker
     * S: Staker
     * PF: Includes priority fee
     * nPF: No priority fee
     * EX: Includes executor execution
     * nEX: Does not include executor execution
     * ID: Uses a NameService identity
     * AD: Uses an address
     */

    function test__unit_revert__dispersePay__InvalidSignature_evvmID()
        external
    {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            COMMON_USER_NO_STAKER_1.PrivateKey,
            Erc191TestBuilder.buildMessageSignedForDispersePay(
                /* 🢃 different evvmID 🢃 */
                core.getEvvmID() + 1,
                toData,
                ETHER_ADDRESS,
                amount,
                priorityFee,
                address(0),
                address(0),
                0,
                false
            )
        );
        bytes memory signaturePay = Erc191TestBuilder.buildERC191Signature(
            v,
            r,
            s
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signaturePay
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InvalidSignature_signer()
        external
    {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            /* 🢃 different signer 🢃 */
            COMMON_USER_NO_STAKER_3,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);
        vm.expectRevert(CoreError.InvalidSignature.selector);
        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InvalidSignature_hashList()
        external
    {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        CoreStructs.DispersePayMetadata[]
            memory toDataFake = new CoreStructs.DispersePayMetadata[](1);

        toDataFake[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            /* 🢃 causes different hashList 🢃 */
            toDataFake,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);
        vm.expectRevert(CoreError.InvalidSignature.selector);
        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InvalidSignature_token() external {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            /* 🢃 different token 🢃 */
            PRINCIPAL_TOKEN_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false
        );
        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);
        vm.expectRevert(CoreError.InvalidSignature.selector);
        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InvalidSignature_amount()
        external
    {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            /* 🢃 different amount 🢃 */
            amount + 1,
            priorityFee,
            address(0),
            address(0),
            0,
            false
        );

        vm.expectRevert(CoreError.InvalidSignature.selector);
        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InvalidSignature_priorityFee()
        external
    {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            amount,
            /* 🢃 different priorityFee 🢃 */
            priorityFee + 1,
            address(0),
            address(0),
            0,
            false
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);
        vm.expectRevert(CoreError.InvalidSignature.selector);
        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InvalidSignature_nonce() external {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            /* 🢃 different nonce 🢃 */
            address(0),
            address(0),
            67,
            false
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);
        vm.expectRevert(CoreError.InvalidSignature.selector);
        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InvalidSignature_isAsyncExec()
        external
    {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            /* 🢃 different isAsyncExec 🢃 */
            true
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);
        vm.expectRevert(CoreError.InvalidSignature.selector);
        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InvalidSignature_executor()
        external
    {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            /* 🢃 different executor 🢃 */
            COMMON_USER_NO_STAKER_3.Address,
            address(0),
            0,
            false
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);
        vm.expectRevert(CoreError.InvalidSignature.selector);
        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__AsyncNonceAlreadyUsed() external {
        _addBalance(COMMON_USER_NO_STAKER_1, ETHER_ADDRESS, 0.1 ether, 0 ether);

        _executeFn_evvm_pay(
            COMMON_USER_NO_STAKER_1,
            COMMON_USER_NO_STAKER_3.Address,
            "",
            ETHER_ADDRESS,
            0.1 ether,
            0 ether,
            address(0),
            address(0),
            67,
            true,
            COMMON_USER_NO_STAKER_3.Address
        );

        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            /* 🢃 nonce already used 🢃 */
            67,
            true
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.AsyncNonceAlreadyUsed.selector);

        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            /* 🢃 nonce already used 🢃 */
            67,
            true,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__SyncNonceMismatch() external {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            /* 🢃 wrong nonce 🢃 */
            999999999999999999,
            false
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.SyncNonceMismatch.selector);

        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            /* 🢃 wrong nonce 🢃 */
            999999999999999999,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InsufficientBalance_amount()
        external
    {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            /* 🢃 amount for [0] too high 🢃 */
            amount: amount + priorityFee,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            /* 🢃 amount for [1] too high 🢃 */
            amount: amount + priorityFee,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            /* 🢃 amount too high 🢃 */
            (amount + priorityFee) * 2,
            priorityFee,
            address(0),
            address(0),
            0,
            false
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.InsufficientBalance.selector);

        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            /* 🢃 amount too high 🢃 */
            (amount + priorityFee) * 2,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InsufficientBalance_priorityFee()
        external
    {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 2,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            amount,
            /* 🢃 priorityFee too high 🢃 */
            (amount + priorityFee) * 2,
            address(0),
            address(0),
            0,
            false
        );

        vm.startPrank(COMMON_USER_STAKER.Address);

        vm.expectRevert(CoreError.InsufficientBalance.selector);

        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            /* 🢃 priorityFee too high 🢃 */
            (amount + priorityFee) * 2,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__InvalidAmount() external {
        (uint256 amount, uint256 priorityFee) = _addBalance(
            COMMON_USER_NO_STAKER_1,
            ETHER_ADDRESS,
            0.10 ether,
            0.01 ether
        );

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: amount / 5,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: amount / 5,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.InvalidAmount.selector);

        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            ETHER_ADDRESS,
            amount,
            priorityFee,
            address(0),
            address(0),
            0,
            false,
            signature
        );

        vm.stopPrank();

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_1.Address, ETHER_ADDRESS),
            amount + priorityFee,
            "Sender balance must be the same because pay reverted"
        );

        assertEq(
            core.getBalance(COMMON_USER_NO_STAKER_2.Address, ETHER_ADDRESS),
            0,
            "Receiver balance must be zero because pay reverted"
        );
    }

    function test__unit_revert__dispersePay__TokenIsDeniedForExecution_denyList()
        external
    {
        vm.startPrank(ADMIN.Address);
        core.proposeListStatus(0x02); // Activate denyList
        skip(1 days + 1); // Skip timelock
        core.acceptListStatusProposal();
        core.setTokenStatusOnDenyList(address(67), true);
        vm.stopPrank();

        _addBalance(COMMON_USER_NO_STAKER_1, address(67), 100, 0);

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: 50,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: 50,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            address(67),
            100,
            0,
            address(0),
            address(0),
            0,
            false
        );

        vm.expectRevert(CoreError.TokenIsDeniedForExecution.selector);

        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            address(67),
            100,
            0,
            address(0),
            address(0),
            0,
            false,
            signature
        );
    }

    function test__unit_revert__dispersePay__TokenIsDeniedForExecution_allowList()
        external
    {
        vm.startPrank(ADMIN.Address);
        core.proposeListStatus(0x01); // Activate allowList
        skip(1 days + 1); // Skip timelock
        core.acceptListStatusProposal();
        vm.stopPrank();

        _addBalance(COMMON_USER_NO_STAKER_1, address(67), 100, 0);

        CoreStructs.DispersePayMetadata[]
            memory toData = new CoreStructs.DispersePayMetadata[](2);

        toData[0] = CoreStructs.DispersePayMetadata({
            amount: 50,
            to_address: COMMON_USER_NO_STAKER_2.Address,
            to_identity: ""
        });

        toData[1] = CoreStructs.DispersePayMetadata({
            amount: 50,
            to_address: address(0),
            to_identity: "dummy"
        });

        bytes memory signature = _executeSig_evvm_dispersePay(
            COMMON_USER_NO_STAKER_1,
            toData,
            address(67),
            100,
            0,
            address(0),
            address(0),
            0,
            false
        );

        vm.expectRevert(CoreError.TokenIsDeniedForExecution.selector);

        core.dispersePay(
            COMMON_USER_NO_STAKER_1.Address,
            toData,
            address(67),
            100,
            0,
            address(0),
            address(0),
            0,
            false,
            signature
        );
    }
}
