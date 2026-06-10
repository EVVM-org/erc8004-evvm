// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {
    CoreStructs
} from "@evvm/testnet-contracts/library/structs/CoreStructs.sol";

abstract contract BaseInputs {
    address admin = 0x5cBf2D4Bbf834912Ad0bD59980355b57695e8309;
    address goldenFisher = 0x5cBf2D4Bbf834912Ad0bD59980355b57695e8309;
    address activator = 0x5cBf2D4Bbf834912Ad0bD59980355b57695e8309;

    CoreStructs.EvvmMetadata inputMetadata =
        CoreStructs.EvvmMetadata({
            EvvmName: "EVVM",
            // evvmID will be set to 0, and it will be assigned when you register the evvm
            EvvmID: 0,
            principalTokenName: "Mate Token",
            principalTokenSymbol: "MATE",
            principalTokenAddress: 0x0000000000000000000000000000000000000001,
            totalSupply: 2033333333000000000000000000,
            eraTokens: 1016666666500000000000000000,
            reward: 5000000000000000000
        });
}
