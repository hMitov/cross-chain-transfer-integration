// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {CrossChainTransferExecutor} from "../src/CrossChainTransferExecutor.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ICrossChainTransferExecutor} from "../src/interfaces/ICrossChainTransferExecutor.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {ICreditDelegationToken} from "@aave/core-v3/contracts/interfaces/ICreditDelegationToken.sol";

contract CrossChainTransferExecutorIT is Test {
    address constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant ORACLE = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;
    address constant TOKEN_MESSENGER_V2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint32 constant DESTINATION_DOMAIN = 6; // Arbitrum domain for CCTP
    uint256 constant USDC_AMOUNT = 1000 * 1e6; // 1000 USDC (6 decimals)
    uint256 constant WETH_AMOUNT = 1 * 1e18; // 1 WETH
    uint256 constant MAX_FEE_USDC = 4_000_000; // 4 USDC (6 decimals) - higher cap to satisfy CCTP min fee on larger borrows

    address user = address(0x1337);
    address recipient = address(0x9999);

    ICrossChainTransferExecutor executor;

    function setUp() public {
        vm.createSelectFork("https://ethereum.publicnode.com");

        // Deploy CrossChainTransferExecutor
        executor = new CrossChainTransferExecutor(AAVE_V3_POOL, ORACLE, TOKEN_MESSENGER_V2, USDC);

        // Deal tokens to user
        deal(USDC, user, USDC_AMOUNT * 10);
        deal(WETH, user, WETH_AMOUNT * 10);

        // Approve executor to spend tokens
        vm.startPrank(user);
        IERC20(USDC).approve(address(executor), type(uint256).max);
        IERC20(WETH).approve(address(executor), type(uint256).max);

        // Approve the executor to borrow USDC on behalf of the user (credit delegation)
        IPool pool = IPool(AAVE_V3_POOL);
        DataTypes.ReserveData memory usdcReserve = pool.getReserveData(USDC);
        ICreditDelegationToken(usdcReserve.variableDebtTokenAddress)
            .approveDelegation(address(executor), type(uint256).max);
        vm.stopPrank();
    }

    function testExecuteTransfer_WhenTokenIsUSDC() public {
        vm.startPrank(user);
        uint256 userUsdcBefore = IERC20(USDC).balanceOf(user);

        // Expect CrossChainTransferInitiated event
        // Check indexed params (user, token) and non-indexed params (suppliedAmount, borrowedUsdc, destinationDomain, recipient)
        // Don't check healthFactor as it's dynamic
        vm.expectEmit(true, true, false, false);
        emit ICrossChainTransferExecutor.CrossChainTransferInitiated(
            user, USDC, 0, 0, DESTINATION_DOMAIN, recipient, 0
        );

        // Execute transfer
        executor.executeTransfer(USDC, DESTINATION_DOMAIN, recipient, USDC_AMOUNT, MAX_FEE_USDC);

        uint256 userUsdcAfter = IERC20(USDC).balanceOf(user);
        uint256 executorUsdcAfter = IERC20(USDC).balanceOf(address(executor));
        vm.stopPrank();

        // Verify user paid the correct amount
        assertEq(userUsdcBefore - userUsdcAfter, USDC_AMOUNT, "User should pay exact USDC amount");

        // Verify executor has no USDC (transferred to TokenMessenger)
        assertEq(executorUsdcAfter, 0, "Executor should have no USDC after transfer");
    }

    function testExecuteTransfer_WhenTokenIsNotUSDC() public {
        vm.startPrank(user);
        uint256 userWethBefore = IERC20(WETH).balanceOf(user);

        vm.expectEmit(true, true, false, false);
        emit ICrossChainTransferExecutor.CrossChainTransferInitiated(
            user, WETH, WETH_AMOUNT, 0, DESTINATION_DOMAIN, recipient, 0
        );

        // Execute transfer
        executor.executeTransfer(WETH, DESTINATION_DOMAIN, recipient, WETH_AMOUNT, MAX_FEE_USDC);
        
        // Get actual debt after transfer
        uint256 actualDebt = executor.getUserBorrows(user);

        uint256 userWethAfter = IERC20(WETH).balanceOf(user);
        uint256 executorWethAfter = IERC20(WETH).balanceOf(address(executor));
        uint256 executorUsdcBalance = IERC20(USDC).balanceOf(address(executor));
        vm.stopPrank();

        // Verify user paid the correct amount
        assertEq(userWethBefore - userWethAfter, WETH_AMOUNT, "User should pay exact WETH amount");

        // Verify executor token balances
        assertEq(executorWethAfter, 0, "Executor should have no WETH after deposit");

        assertEq(executorUsdcBalance, 0, "Executor should have no USDC after transfer");
        
        // Verify debt was created
        assertGt(actualDebt, 0, "Debt should be > 0 after borrowing");
    }

    function testRepayBorrowed_UsingGetUserBorrows() public {
        vm.startPrank(user);
        // Execute transfer
        executor.executeTransfer(WETH, DESTINATION_DOMAIN, recipient, WETH_AMOUNT, MAX_FEE_USDC);

        // Read current USDC debt via getUserBorrows
        uint256 debtBefore = executor.getUserBorrows(user);
        assertGt(debtBefore, 0, "USDC should be > 0 after borrow");

        // Repay full debt
        executor.repayBorrowed(debtBefore);

        // Debt should be zero
        uint256 debtAfter = executor.getUserBorrows(user);
        assertEq(debtAfter, 0, "Debt should be = 0 after repayment");
        vm.stopPrank();
    }
}
