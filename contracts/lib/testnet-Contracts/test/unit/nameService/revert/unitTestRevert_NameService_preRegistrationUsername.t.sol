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

contract unitTestRevert_NameService_preRegistrationUsername is Test, Constants {
    function executeBeforeSetUp() internal override {
        
    }

    function _addBalance(
        AccountData memory user,
        uint256 priorityFeeAmount
    ) private returns (uint256 priorityFee) {
        core.addBalance(
            user.Address,
            PRINCIPAL_TOKEN_ADDRESS,
            priorityFeeAmount
        );

        priorityFee = priorityFeeAmount;
    }

    function test__unit_revert__preRegistrationUsername__InvalidSignatureOnNameService_evvmID()
        external
    {
        uint256 nonce = 1001;

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            COMMON_USER_NO_STAKER_1.PrivateKey,
            Erc191TestBuilder.buildMessageSignedForPreRegistrationUsername(
                /* 🢃 different evvmID 🢃 */
                core.getEvvmID() + 1,
                keccak256(abi.encodePacked("test", uint256(10101))),
                address(0),
                address(0),
                nonce
            )
        );
        bytes memory signatureNameService = Erc191TestBuilder
            .buildERC191Signature(v, r, s);

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.preRegistrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            keccak256(abi.encodePacked("test", uint256(10101))),
            address(0),
            address(0),
            nonce,
            signatureNameService,
            0,
            0,
            hex""
        );

        vm.stopPrank();

        (address user, ) = nameService.getIdentityBasicMetadata(
            string.concat(
                "@",
                AdvancedStrings.bytes32ToString(
                    keccak256(abi.encodePacked("test", uint256(10101)))
                )
            )
        );

        assertEq(user, address(0), "username should not be preregistered");
    }

    function test__unit_revert__preRegistrationUsername__InvalidSignatureOnNameService_signer()
        external
    {
        string memory username = "test";
        uint256 lockNumber = 10101;
        uint256 nonce = 1001;
        (
            bytes memory signatureNameService,

        ) = _executeSig_nameService_preRegistrationUsername(
                /* 🢃 different signer 🢃 */
                COMMON_USER_NO_STAKER_2,
                username,
                lockNumber,
                address(0),
                address(0),
                nonce,
                0,
                0
            );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.preRegistrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            keccak256(abi.encodePacked(username, uint256(lockNumber))),
            address(0),
            address(0),
            nonce,
            signatureNameService,
            0,
            0,
            hex""
        );

        vm.stopPrank();

        (address user, ) = nameService.getIdentityBasicMetadata(
            string.concat(
                "@",
                AdvancedStrings.bytes32ToString(
                    keccak256(abi.encodePacked(username, uint256(lockNumber)))
                )
            )
        );

        assertEq(user, address(0), "username should not be preregistered");
    }

    function test__unit_revert__preRegistrationUsername__InvalidSignatureOnNameService_nameServiceNonce()
        external
    {
        string memory username = "test";
        uint256 lockNumber = 10101;
        uint256 nonce = 1001;
        (
            bytes memory signatureNameService,

        ) = _executeSig_nameService_preRegistrationUsername(
                COMMON_USER_NO_STAKER_1,
                username,
                lockNumber,
                address(0),
                address(0),
                /* 🢃 different nonce 🢃 */
                nonce + 67,
                0,
                0
            );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.preRegistrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            keccak256(abi.encodePacked(username, uint256(lockNumber))),
            address(0),
            address(0),
            nonce,
            signatureNameService,
            0,
            0,
            hex""
        );

        vm.stopPrank();

        (address user, ) = nameService.getIdentityBasicMetadata(
            string.concat(
                "@",
                AdvancedStrings.bytes32ToString(
                    keccak256(abi.encodePacked(username, uint256(lockNumber)))
                )
            )
        );

        assertEq(user, address(0), "username should not be preregistered");
    }

    function test__unit_revert__preRegistrationUsername__InvalidSignatureOnNameService_hashUsername()
        external
    {
        string memory username = "test";
        uint256 lockNumber = 10101;
        uint256 nonce = 1001;
        (
            bytes memory signatureNameService,

        ) = _executeSig_nameService_preRegistrationUsername(
                COMMON_USER_NO_STAKER_1,
                /* 🢃 different hash 🢃 */
                "wrongusername",
                67,
                address(0),
                address(0),
                nonce,
                0,
                0
            );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.preRegistrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            keccak256(abi.encodePacked(username, uint256(lockNumber))),
            address(0),
            address(0),
            nonce,
            signatureNameService,
            0,
            0,
            hex""
        );

        vm.stopPrank();

        (address user, ) = nameService.getIdentityBasicMetadata(
            string.concat(
                "@",
                AdvancedStrings.bytes32ToString(
                    keccak256(abi.encodePacked(username, uint256(lockNumber)))
                )
            )
        );

        assertEq(user, address(0), "username should not be preregistered");
    }

    function test__unit_revert__preRegistrationUsername_NonceAlreadyUsed()
        external
    {
        string memory username = "test";
        uint256 lockNumber = 10101;
        uint256 nonce = 1001;

        _executeFn_nameService_preRegistrationUsername(
            COMMON_USER_NO_STAKER_1,
            "testdifferent",
            67,
            address(0),
            address(0),
            nonce
        );

        (
            bytes memory signatureNameService,

        ) = _executeSig_nameService_preRegistrationUsername(
                COMMON_USER_NO_STAKER_1,
                username,
                lockNumber,
                address(0),
                address(0),
                /* 🢃 nonce already used 🢃 */
                nonce,
                0,
                0
            );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.AsyncNonceAlreadyUsed.selector);
        nameService.preRegistrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            keccak256(abi.encodePacked(username, lockNumber)),
            /* 🢃 nonce already used 🢃 */
            address(0),
            address(0),
            nonce,
            signatureNameService,
            0,
            0,
            hex""
        );

        vm.stopPrank();

        (address user, ) = nameService.getIdentityBasicMetadata(
            string.concat(
                "@",
                AdvancedStrings.bytes32ToString(
                    keccak256(abi.encodePacked(username, uint256(lockNumber)))
                )
            )
        );

        assertEq(user, address(0), "username should not be preregistered");
    }

    function test__unit_revert__preRegistrationUsername__InvalidSignature_fromEvvm()
        external
    {
        _addBalance(COMMON_USER_NO_STAKER_2, 5 ether);
        string memory username = "test";
        uint256 lockNumber = 10101;
        uint256 nonce = 1001;
        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_preRegistrationUsername(
                COMMON_USER_NO_STAKER_1,
                username,
                lockNumber,
                address(0),
                address(0),
                nonce,
                0.0001 ether,
                6767
            );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.InvalidSignature.selector);
        nameService.preRegistrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            keccak256(abi.encodePacked(username, uint256(lockNumber))),
            address(0),
            address(0),
            nonce,
            signatureNameService,
            /* 🢃 different priority fee 🢃 */
            1 ether,
            6767,
            signaturePay
        );

        vm.stopPrank();

        (address user, ) = nameService.getIdentityBasicMetadata(
            string.concat(
                "@",
                AdvancedStrings.bytes32ToString(
                    keccak256(abi.encodePacked(username, uint256(lockNumber)))
                )
            )
        );

        assertEq(user, address(0), "username should not be preregistered");
    }

    function test__unit_revert__preRegistrationUsername__InsufficientBalance_fromEvvm()
        external
    {
        string memory username = "test";
        uint256 lockNumber = 10101;
        uint256 nonce = 1001;
        (
            bytes memory signatureNameService,
            bytes memory signaturePay
        ) = _executeSig_nameService_preRegistrationUsername(
                COMMON_USER_NO_STAKER_1,
                username,
                lockNumber,
                address(0),
                address(0),
                nonce,
                0.1 ether,
                676767
            );

        vm.startPrank(COMMON_USER_NO_STAKER_2.Address);

        vm.expectRevert(CoreError.InsufficientBalance.selector);
        /* 🢃 insufficient balance to cover priority fee 🢃 */
        nameService.preRegistrationUsername(
            COMMON_USER_NO_STAKER_1.Address,
            keccak256(abi.encodePacked(username, uint256(lockNumber))),
            address(0),
            address(0),
            nonce,
            signatureNameService,
            0.1 ether,
            676767,
            signaturePay
        );

        vm.stopPrank();

        (address user, ) = nameService.getIdentityBasicMetadata(
            string.concat(
                "@",
                AdvancedStrings.bytes32ToString(
                    keccak256(abi.encodePacked(username, uint256(lockNumber)))
                )
            )
        );

        assertEq(user, address(0), "username should not be preregistered");
    }
}
