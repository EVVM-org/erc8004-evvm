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

contract unitTestRevert_NameService_addCustomMetadata is Test, Constants {
    AccountData COMMON_USER_NO_STAKER_3 = WILDCARD_USER;

    uint256 offerID;

    string constant USERNAME = "test";

    function executeBeforeSetUp() internal override {
        _executeFn_nameService_registrationUsername(
            COMMON_USER_NO_STAKER_1,
            USERNAME,
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
    }

    function addBalance(
        AccountData memory user,
        uint256 priorityFeeAmount
    )
        private
        returns (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        )
    {
        core.addBalance(
            user.Address,
            PRINCIPAL_TOKEN_ADDRESS,
            nameService.getPriceToAddCustomMetadata() + priorityFeeAmount
        );

        totalPriceToAddCustomMetadata = nameService
            .getPriceToAddCustomMetadata();
        totalPriorityFeeAmount = priorityFeeAmount;
    }

    function test__unit_revert__addCustomMetadata__InvalidSignatureOnNameService_evvmID()
        external
    {
        (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        ) = addBalance(COMMON_USER_NO_STAKER_1, 0.0001 ether);

        string memory customMetadata = string.concat(USERNAME, ">1");
        uint256 nonce = 100010001;
        uint256 noncePay = 1001;

        uint8 v;
        bytes32 r;
        bytes32 s;
        bytes memory signatureNameService;
        bytes memory signaturePay;

        (v, r, s) = vm.sign(
            COMMON_USER_NO_STAKER_1.PrivateKey,
            Erc191TestBuilder.buildMessageSignedForAddCustomMetadata(
                /* 🢃 different evvmID 🢃 */
                core.getEvvmID() + 1,
                USERNAME,
                customMetadata,
                address(0),
                address(0),
                nonce
            )
        );
        signatureNameService = Erc191TestBuilder.buildERC191Signature(v, r, s);

        signaturePay = _executeSig_evvm_pay(
            COMMON_USER_NO_STAKER_1,
            address(nameService),
            "",
            PRINCIPAL_TOKEN_ADDRESS,
            nameService.getPriceToAddCustomMetadata(),
            totalPriorityFeeAmount,
            address(nameService),
            address(0),
            noncePay,
            true
        );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.addCustomMetadata(
            COMMON_USER_NO_STAKER_1.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            totalPriorityFeeAmount,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            totalPriceToAddCustomMetadata + totalPriorityFeeAmount
        );
    }

    function test__unit_revert__addCustomMetadata__InvalidSignatureOnNameService_signer()
        external
    {
        (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        ) = addBalance(COMMON_USER_NO_STAKER_1, 0.0001 ether);

        string memory customMetadata = string.concat(USERNAME, ">1");
        uint256 nonce = 100010001;
        uint256 noncePay = 1001;

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_addCustomMetadata(
                /* 🢃 different signer 🢃 */
                COMMON_USER_NO_STAKER_2,
                USERNAME,
                customMetadata,
                address(0),
                address(0),
                nonce,
                totalPriorityFeeAmount,
                noncePay
            );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.addCustomMetadata(
            COMMON_USER_NO_STAKER_1.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            totalPriorityFeeAmount,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            totalPriceToAddCustomMetadata + totalPriorityFeeAmount
        );
    }

    function test__unit_revert__addCustomMetadata__InvalidSignatureOnNameService_identity()
        external
    {
        (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        ) = addBalance(COMMON_USER_NO_STAKER_1, 0.0001 ether);

        string memory customMetadata = string.concat(USERNAME, ">1");
        uint256 nonce = 100010001;
        uint256 noncePay = 1001;

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_addCustomMetadata(
                COMMON_USER_NO_STAKER_1,
                /* 🢃 different identity 🢃 */
                "differentIdentity",
                customMetadata,
                address(0),
                address(0),
                nonce,
                totalPriorityFeeAmount,
                noncePay
            );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.addCustomMetadata(
            COMMON_USER_NO_STAKER_1.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            totalPriorityFeeAmount,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            totalPriceToAddCustomMetadata + totalPriorityFeeAmount
        );
    }

    function test__unit_revert__addCustomMetadata__InvalidSignatureOnNameService_value()
        external
    {
        (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        ) = addBalance(COMMON_USER_NO_STAKER_1, 0.0001 ether);

        string memory customMetadata = string.concat(USERNAME, ">1");
        uint256 nonce = 100010001;
        uint256 noncePay = 1001;

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_addCustomMetadata(
                COMMON_USER_NO_STAKER_1,
                USERNAME,
                /* 🢃 different value 🢃 */
                string.concat(USERNAME, ">2"),
                address(0),
                address(0),
                nonce,
                totalPriorityFeeAmount,
                noncePay
            );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.addCustomMetadata(
            COMMON_USER_NO_STAKER_1.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            totalPriorityFeeAmount,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            totalPriceToAddCustomMetadata + totalPriorityFeeAmount
        );
    }

    function test__unit_revert__addCustomMetadata__InvalidSignatureOnNameService_nameServiceNonce()
        external
    {
        (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        ) = addBalance(COMMON_USER_NO_STAKER_1, 0.0001 ether);

        string memory customMetadata = string.concat(USERNAME, ">1");
        uint256 nonce = 100010001;
        uint256 noncePay = 1001;

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_addCustomMetadata(
                COMMON_USER_NO_STAKER_1,
                USERNAME,
                customMetadata,
                address(0),
                address(0),
                /* 🢃 different nonce 🢃 */
                nonce + 1,
                totalPriorityFeeAmount,
                noncePay
            );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.addCustomMetadata(
            COMMON_USER_NO_STAKER_1.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            totalPriorityFeeAmount,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            totalPriceToAddCustomMetadata + totalPriorityFeeAmount
        );
    }

    function test__unit_revert__addCustomMetadata__UserIsNotOwnerOfIdentity()
        external
    {
        (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        ) = /* 🢃 different user (not owner) 🢃 */ addBalance(
                COMMON_USER_NO_STAKER_2,
                0.0001 ether
            );

        string memory customMetadata = string.concat(USERNAME, ">1");
        uint256 nonce = 100010001;
        uint256 noncePay = 1001;

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_addCustomMetadata(
                /* 🢃 different user (not owner) 🢃 */
                COMMON_USER_NO_STAKER_2,
                USERNAME,
                customMetadata,
                address(0),
                address(0),
                nonce,
                totalPriorityFeeAmount,
                noncePay
            );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(NameServiceError.UserIsNotOwnerOfIdentity.selector);
        nameService.addCustomMetadata(
            /* 🢃 different user (not owner) 🢃 */
            COMMON_USER_NO_STAKER_2.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            totalPriorityFeeAmount,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_2.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            totalPriceToAddCustomMetadata + totalPriorityFeeAmount
        );
    }

    function test__unit_revert__addCustomMetadata__EmptyCustomMetadata()
        external
    {
        (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        ) = addBalance(COMMON_USER_NO_STAKER_1, 0.0001 ether);

        /* 🢃 empty custom metadata 🢃 */
        string memory customMetadata = "";
        uint256 nonce = 100010001;
        uint256 noncePay = 1001;

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_addCustomMetadata(
                COMMON_USER_NO_STAKER_1,
                USERNAME,
                customMetadata,
                address(0),
                address(0),
                nonce,
                totalPriorityFeeAmount,
                noncePay
            );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(NameServiceError.EmptyCustomMetadata.selector);
        nameService.addCustomMetadata(
            COMMON_USER_NO_STAKER_1.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            totalPriorityFeeAmount,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            totalPriceToAddCustomMetadata + totalPriorityFeeAmount
        );
    }

    function test__unit_revert__addCustomMetadata_NonceAlreadyUsed() external {
        (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        ) = addBalance(COMMON_USER_NO_STAKER_1, 0.0001 ether);

        string memory customMetadata = string.concat(USERNAME, ">1");
        /* 🢃 reused nonce 🢃 */
        uint256 nonce = uint256(
            0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff1
        );
        uint256 noncePay = 1001;

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_addCustomMetadata(
                COMMON_USER_NO_STAKER_1,
                USERNAME,
                customMetadata,
                address(0),
                address(0),
                nonce,
                totalPriorityFeeAmount,
                noncePay
            );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(CoreError.AsyncNonceAlreadyUsed.selector);
        nameService.addCustomMetadata(
            COMMON_USER_NO_STAKER_1.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            totalPriorityFeeAmount,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            totalPriceToAddCustomMetadata + totalPriorityFeeAmount
        );
    }

    function test__unit_revert__addCustomMetadata__InvalidSignature_fromEvvm()
        external
    {
        (
            uint256 totalPriceToAddCustomMetadata,
            uint256 totalPriorityFeeAmount
        ) = addBalance(COMMON_USER_NO_STAKER_1, 0.0001 ether);

        string memory customMetadata = string.concat(USERNAME, ">1");
        uint256 nonce = 100010001;
        uint256 noncePay = 1001;

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_addCustomMetadata(
                COMMON_USER_NO_STAKER_1,
                USERNAME,
                customMetadata,
                address(0),
                address(0),
                nonce,
                /* 🢃 different totalPriorityFee 🢃 */
                totalPriorityFeeAmount + 50,
                /* 🢃 different noncePay 🢃 */
                noncePay + 1
            );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.addCustomMetadata(
            COMMON_USER_NO_STAKER_1.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            totalPriorityFeeAmount,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            totalPriceToAddCustomMetadata + totalPriorityFeeAmount
        );
    }

    function test__unit_revert__addCustomMetadata__InsufficientBalance_fromEvvm()
        external
    {
        string memory customMetadata = string.concat(USERNAME, ">1");
        uint256 nonce = 100010001;
        uint256 noncePay = 1001;

        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_addCustomMetadata(
                COMMON_USER_NO_STAKER_1,
                USERNAME,
                customMetadata,
                address(0),
                address(0),
                nonce,
                0,
                noncePay
            );

        vm.startPrank(COMMON_USER_NO_STAKER_3.Address);

        vm.expectRevert(CoreError.InsufficientBalance.selector);
        nameService.addCustomMetadata(
            COMMON_USER_NO_STAKER_1.Address,
            USERNAME,
            customMetadata,
            address(0),
            address(0),
            nonce,
            signatureNameService,
            0,
            noncePay,
            signaturePay
        );

        vm.stopPrank();

        string memory customMetadataInfo = nameService
            .getSingleCustomMetadataOfIdentity(USERNAME, 0);

        assert(
            bytes(customMetadataInfo).length == bytes("").length &&
                keccak256(bytes(customMetadataInfo)) == keccak256(bytes(""))
        );

        assertEq(nameService.getCustomMetadataMaxSlotsOfIdentity(USERNAME), 0);

        assertEq(
            core.getBalance(
                COMMON_USER_NO_STAKER_1.Address,
                PRINCIPAL_TOKEN_ADDRESS
            ),
            0
        );
    }
}
