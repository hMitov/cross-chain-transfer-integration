// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";
import {CrossChainTransferExecutor} from "../src/CrossChainTransferExecutor.sol";
import {EnvLoader} from "./EnvLoader.s.sol";

/**
 * @title DeployCrossChainTransferExecutorScript
 * @notice Script to deploy the CrossChainTransferExecutor contract
 */
contract DeployCrossChainTransferExecutorScript is EnvLoader {
    /// @notice Deployer's private key
    uint256 private privateKey;
    /// @notice Aave V3 pool address on Sepolia
    address private poolAddress;
    /// @notice Aave V3 oracle address on Sepolia
    address private oracleAddress;
    /// @notice CCTP token messenger address on Sepolia
    address private tokenMessengerAddress;
    /// @notice USDC address on Sepolia
    address private usdcAddress;

    /**
     * @notice Deploy the CrossChainTransferExecutor contract
     * @dev Loads environment variables and deploys the contract
     */
    function run() public {
        loadEnvVars();

        vm.startBroadcast(privateKey);
        CrossChainTransferExecutor executor =
            new CrossChainTransferExecutor(poolAddress, oracleAddress, tokenMessengerAddress, usdcAddress);
        vm.stopBroadcast();

        console.log("CrossChainTransferExecutor deployed to:", address(executor));
        console.log("Pool address:", poolAddress);
        console.log("Oracle address:", oracleAddress);
        console.log("TokenMessenger address:", tokenMessengerAddress);
        console.log("USDC address:", usdcAddress);
    }

    /**
     * @notice Load environment variables
     * @dev Sets privateKey and poolAddress from env vars
     */
    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("DEPLOYER_PRIVATE_KEY");
        poolAddress = getEnvAddress("ETHEREUM_SEPOLIA_POOL_ADDRESS");
        oracleAddress = getEnvAddress("ETHEREUM_SEPOLIA_ORACLE_ADDRESS");
        tokenMessengerAddress = getEnvAddress("ETHEREUM_SEPOLIA_TOKEN_MESSENGER_ADDRESS");
        usdcAddress = getEnvAddress("ETHEREUM_SEPOLIA_USDC_ADDRESS");
    }
}
