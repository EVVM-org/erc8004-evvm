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
import "@evvm/testnet-contracts/library/utils/AdvancedStrings.sol";
import "@evvm/testnet-contracts/library/structs/NameServiceStructs.sol";

import {
    NameService
} from "@evvm/testnet-contracts/contracts/nameService/NameService.sol";
import {
    NameServiceError
} from "@evvm/testnet-contracts/library/errors/NameServiceError.sol";
import {CoreError} from "@evvm/testnet-contracts/library/errors/CoreError.sol";

import {CoreError} from "@evvm/testnet-contracts/library/errors/CoreError.sol";

contract unitTestRevert_NameService_registrationUsername is Test, Constants {
    function executeBeforeSetUp() internal override {}

    function _addBalance(
        address user,
        string memory username,
        uint256 priorityFeeAmount
    )
        private
        returns (uint256 registrationPrice, uint256 totalPriorityFeeAmount)
    {
        core.addBalance(
            user,
            PRINCIPAL_TOKEN_ADDRESS,
            nameService.getPriceOfRegistration(username) + priorityFeeAmount
        );

        registrationPrice = nameService.getPriceOfRegistration(username);
        totalPriorityFeeAmount = priorityFeeAmount;
    }

    function test__unit_revert__registrationUsername__InvalidSignatureOnNameService_evvmID()
        external
    {
        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        (
            uint256 registrationPrice,
            uint256 totalPriorityFeeAmount
        ) = _addBalance(COMMON_USER_NO_STAKER_1.Address, "test", 0.001 ether);

        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = vm.sign(
            COMMON_USER_NO_STAKER_1.PrivateKey,
            Erc191TestBuilder.buildMessageSignedForRegistrationUsername(
                core.getEvvmID(),
                "test",
                777,
                address(0),
                address(0),
                222
            )
        );
        bytes memory signatureNameService = Erc191TestBuilder
            .buildERC191Signature(v, r, s);

        (v, r, s) = vm.sign(
            COMMON_USER_NO_STAKER_1.PrivateKey,
            Erc191TestBuilder.buildMessageSignedForPay(
                /* 🢃 different evvmID 🢃 */
                core.getEvvmID() + 1,
                address(nameService),
                "",
                PRINCIPAL_TOKEN_ADDRESS,
                nameService.getPriceOfRegistration("test"),
                totalPriorityFeeAmount,
                address(nameService),
                address(0),
                222,
                true
            )
        );
        bytes memory signaturePay = Erc191TestBuilder.buildERC191Signature(
            v,
            r,
            s
        );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);
        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "test",
            777,
            address(0),
            address(0),
            222,
            signatureNameService,
            totalPriorityFeeAmount,
            222,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, uint256 expirationDate) = nameService
            .getIdentityBasicMetadata("test");

        assertEq(owner, address(0), "username should not be reregistered");

        assertEq(expirationDate, 0, "username expiration date should be zero");
    }

    function test__unit_revert__registrationUsername__InvalidSignatureOnNameService_signer()
        external
    {
        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        (
            uint256 registrationPrice,
            uint256 totalPriorityFeeAmount
        ) = _addBalance(COMMON_USER_NO_STAKER_1.Address, "test", 0.001 ether);

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_registrationUsername(
                /* 🢃 different signer 🢃 */
                COMMON_USER_NO_STAKER_2,
                "test",
                777,
                address(0),
                address(0),
                10101,
                totalPriorityFeeAmount,
                10001
            );

        vm.startPrank(COMMON_USER_STAKER.Address);
        vm.expectRevert();
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "test",
            777,
            address(0),
            address(0),
            10101,
            signatureNameService,
            totalPriorityFeeAmount,
            10001,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, uint256 expirationDate) = nameService
            .getIdentityBasicMetadata("test");

        assertEq(owner, address(0), "username should not be reregistered");

        assertEq(expirationDate, 0, "username expiration date should be zero");
    }

    function test__unit_revert__registrationUsername__InvalidSignatureOnNameService_username()
        external
    {
        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        (
            uint256 registrationPrice,
            uint256 totalPriorityFeeAmount
        ) = _addBalance(COMMON_USER_NO_STAKER_1.Address, "test", 0.001 ether);

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_registrationUsername(
                COMMON_USER_NO_STAKER_1,
                /* 🢃 different username 🢃 */
                "invalid",
                777,
                address(0),
                address(0),
                10101,
                totalPriorityFeeAmount,
                10001
            );

        vm.startPrank(COMMON_USER_STAKER.Address);
        vm.expectRevert();
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "test",
            777,
            address(0),
            address(0),
            10101,
            signatureNameService,
            totalPriorityFeeAmount,
            10001,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, uint256 expirationDate) = nameService
            .getIdentityBasicMetadata("test");

        assertEq(owner, address(0), "username should not be reregistered");

        assertEq(expirationDate, 0, "username expiration date should be zero");
    }

    function test__unit_revert__registrationUsername__InvalidSignatureOnNameService_lockNumber()
        external
    {
        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        (
            uint256 registrationPrice,
            uint256 totalPriorityFeeAmount
        ) = _addBalance(COMMON_USER_NO_STAKER_1.Address, "test", 0.001 ether);

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_registrationUsername(
                COMMON_USER_NO_STAKER_1,
                "test",
                /* 🢃 different lockNumber 🢃 */
                888,
                address(0),
                address(0),
                10101,
                totalPriorityFeeAmount,
                10001
            );

        vm.startPrank(COMMON_USER_STAKER.Address);
        vm.expectRevert();
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "test",
            777,
            address(0),
            address(0),
            10101,
            signatureNameService,
            totalPriorityFeeAmount,
            10001,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, uint256 expirationDate) = nameService
            .getIdentityBasicMetadata("test");

        assertEq(owner, address(0), "username should not be reregistered");

        assertEq(expirationDate, 0, "username expiration date should be zero");
    }

    function test__unit_revert__registrationUsername__InvalidSignatureOnNameService_nameServiceNonce()
        external
    {
        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        (
            uint256 registrationPrice,
            uint256 totalPriorityFeeAmount
        ) = _addBalance(COMMON_USER_NO_STAKER_1.Address, "test", 0.001 ether);

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_registrationUsername(
                COMMON_USER_NO_STAKER_1,
                "test",
                777,
                address(0),
                address(0),
                /* 🢃 different nameServiceNonce 🢃 */
                67,
                totalPriorityFeeAmount,
                10001
            );

        vm.startPrank(COMMON_USER_STAKER.Address);
        vm.expectRevert();
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "test",
            777,
            address(0),
            address(0),
            10101,
            signatureNameService,
            totalPriorityFeeAmount,
            10001,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, uint256 expirationDate) = nameService
            .getIdentityBasicMetadata("test");

        assertEq(owner, address(0), "username should not be reregistered");

        assertEq(expirationDate, 0, "username expiration date should be zero");
    }

    function test__unit_revert__registrationUsername__InvalidUsername()
        external
    {
        /* 🢂 username with invalid character '@' 🢀 */
        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "@test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        (
            uint256 registrationPrice,
            uint256 totalPriorityFeeAmount
        ) = _addBalance(COMMON_USER_NO_STAKER_1.Address, "@test", 0.001 ether);

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_registrationUsername(
                COMMON_USER_NO_STAKER_1,
                "@test",
                777,
                address(0),
                address(0),
                10101,
                totalPriorityFeeAmount,
                10001
            );

        vm.startPrank(COMMON_USER_STAKER.Address);
        vm.expectRevert(NameServiceError.InvalidUsername.selector);
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "@test",
            777,
            address(0),
            address(0),
            10101,
            signatureNameService,
            totalPriorityFeeAmount,
            10001,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, uint256 expirationDate) = nameService
            .getIdentityBasicMetadata("@test");

        assertEq(owner, address(0), "username should not be reregistered");

        assertEq(expirationDate, 0, "username expiration date should be zero");
    }

    function test__unit_revert__registrationUsername__UsernameAlreadyRegistered()
        external
    {
        _executeFn_nameService_registrationUsername(
            COMMON_USER_NO_STAKER_2,
            "test",
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

        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        (
            uint256 registrationPrice,
            uint256 totalPriorityFeeAmount
        ) = _addBalance(COMMON_USER_NO_STAKER_1.Address, "test", 0.001 ether);

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_registrationUsername(
                COMMON_USER_NO_STAKER_1,
                "test",
                777,
                address(0),
                address(0),
                10101,
                totalPriorityFeeAmount,
                10001
            );

        vm.startPrank(COMMON_USER_STAKER.Address);
        vm.expectRevert(NameServiceError.UsernameAlreadyRegistered.selector);
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "test",
            777,
            address(0),
            address(0),
            10101,
            signatureNameService,
            totalPriorityFeeAmount,
            10001,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, ) = nameService.getIdentityBasicMetadata("test");

        assertEq(
            owner,
            COMMON_USER_NO_STAKER_2.Address,
            "username owner should be unchanged"
        );
    }

    function test__unit_revert__registrationUsername_NonceAlreadyUsed()
        external
    {
        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        (
            uint256 registrationPrice,
            uint256 totalPriorityFeeAmount
        ) = _addBalance(COMMON_USER_NO_STAKER_1.Address, "test", 0.001 ether);

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_registrationUsername(
                COMMON_USER_NO_STAKER_1,
                "test",
                777,
                address(0),
                address(0),
                /* 🢃 reuse nonce 111 🢃 */
                111,
                totalPriorityFeeAmount,
                10001
            );

        vm.startPrank(COMMON_USER_STAKER.Address);
        vm.expectRevert(CoreError.AsyncNonceAlreadyUsed.selector);
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "test",
            777,
            address(0),
            address(0),
            /* 🢃 reuse nonce 111 🢃 */
            111,
            signatureNameService,
            totalPriorityFeeAmount,
            10001,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, uint256 expirationDate) = nameService
            .getIdentityBasicMetadata("test");

        assertEq(owner, address(0), "username should not be reregistered");

        assertEq(expirationDate, 0, "username expiration date should be zero");
    }

    function test__unit_revert__registrationUsername__InvalidSignature_fromEvvm()
        external
    {
        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        (
            uint256 registrationPrice,
            uint256 totalPriorityFeeAmount
        ) = _addBalance(COMMON_USER_NO_STAKER_1.Address, "test", 0.001 ether);

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_registrationUsername(
                COMMON_USER_NO_STAKER_1,
                "test",
                777,
                address(0),
                address(0),
                10101,
                totalPriorityFeeAmount,
                /* 🢃 different evvm nonce 🢃 */
                67
            );

        vm.startPrank(COMMON_USER_STAKER.Address);
        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "test",
            777,
            address(0),
            address(0),
            10101,
            signatureNameService,
            totalPriorityFeeAmount,
            10001,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, uint256 expirationDate) = nameService
            .getIdentityBasicMetadata("test");

        assertEq(owner, address(0), "username should not be reregistered");

        assertEq(expirationDate, 0, "username expiration date should be zero");
    }

    function test__unit_revert__registrationUsername__InsufficientBalance_fromEvvm()
        external
    {
        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "test",
            777,
            address(0),
            address(0),
            111
        );

        skip(30 minutes);

        uint256 registrationPrice = nameService.getPriceOfRegistration("test");
        uint256 totalPriorityFeeAmount = 0.001 ether;

        core.addBalance(
            COMMON_USER_NO_STAKER_1.Address,
            PRINCIPAL_TOKEN_ADDRESS,
            nameService.getPriceOfRegistration("test") / 2 + 0.001 ether
        );

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_registrationUsername(
                COMMON_USER_NO_STAKER_1,
                "test",
                777,
                address(0),
                address(0),
                10101,
                totalPriorityFeeAmount,
                10001
            );

        vm.startPrank(COMMON_USER_STAKER.Address);
        vm.expectRevert(CoreError.InsufficientBalance.selector);
        nameService.registrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            "test",
            777,
            address(0),
            address(0),
            10101,
            signatureNameService,
            totalPriorityFeeAmount,
            10001,
            signaturePay
        );
        vm.stopPrank();

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            registrationPrice / 2 + totalPriorityFeeAmount,
            "user balance should be the same after revert"
        );

        (address owner, uint256 expirationDate) = nameService
            .getIdentityBasicMetadata("test");

        assertEq(owner, address(0), "username should not be reregistered");

        assertEq(expirationDate, 0, "username expiration date should be zero");
    }
}
