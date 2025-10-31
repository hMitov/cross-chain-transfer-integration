# Cross-Chain Transfer Integration

A smart contract system that enables seamless cross-chain token transfers by integrating **Aave V3** lending protocol with **Circle's Cross-Chain Transfer Protocol (CCTP)**. This allows users to transfer USDC across chains either directly or by using collateral (e.g., WETH) to borrow USDC before transferring.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Testing](#testing)
- [Deployment](#deployment)
- [Security](#security)
- [Technical Details](#technical-details)
- [License](#license)

## Overview

The `CrossChainTransferExecutor` contract acts as a bridge between Aave V3 and CCTP, enabling users to:

1. **Direct USDC Transfer**: Transfer USDC directly across chains via CCTP
2. **Collateral-based Transfer**: Supply collateral (e.g., WETH) to Aave, borrow USDC against it, and transfer the borrowed USDC across chains
3. **Debt Management**: Check outstanding debt and repay borrowed amounts

This integration unlocks cross-chain DeFi use cases by allowing users to leverage their assets on one chain to obtain USDC on another chain.

## Architecture

```
┌─────────────┐         ┌──────────────────────┐         ┌──────────┐
│    User     │────────▶│ CrossChainTransfer   │────────▶│   CCTP   │
│             │         │     Executor         │         │ TokenMess│
└─────────────┘         └──────────────────────┘         └──────────┘
                              │
                              ▼
                        ┌─────────────┐
                        │ Aave V3 Pool│
                        └─────────────┘
```

### Key Components

- **CrossChainTransferExecutor**: Main contract that orchestrates the flow
- **Aave V3 Pool**: Lending protocol for collateral supply and USDC borrowing
- **CCTP TokenMessenger**: Circle's protocol for cross-chain USDC transfers
- **Access Control**: Admin and Pauser roles for contract management

## Features

### Core Functionality

- Cross-chain USDC transfers via CCTP
- Collateral-based borrowing from Aave V3
- Automatic LTV (Loan-to-Value) calculations with 95% safety buffer
- Debt tracking and repayment functionality
- Support for multiple collateral tokens

### Security Features

- ReentrancyGuard protection
- Pausable functionality for emergency stops
- Role-based access control (Admin/Pauser)
- Comprehensive input validation
- SafeERC20 for token operations

## Prerequisites

- [Foundry](https://getfoundry.sh/) (tested with latest version)
- Node.js (for dependency management if needed)
- Access to Ethereum RPC endpoint (for testing/deployment)

## Installation

1. **Clone the repository:**
```bash
git clone https://github.com/hMitov/cross-chain-transfer-integration.git
cd cross-chain-transfer-integration
```

2. **Install dependencies:**
```bash
forge install
```

3. **Install submodules** (if using git submodules):
```bash
git submodule update --init --recursive
```

## Usage

### Basic Flow

#### 1. Direct USDC Transfer

If you have USDC, transfer it directly:

```solidity
// Approve executor to spend USDC
IERC20(USDC).approve(address(executor), amount);

// Execute cross-chain transfer
executor.executeTransfer(
    USDC,                    // token address
    destinationDomain,       // e.g., 6 for Arbitrum
    recipient,               // recipient address on destination chain
    amount,                  // amount to transfer
    maxFee                   // maximum CCTP fee
);
```

#### 2. Collateral-based Transfer

Use collateral (e.g., WETH) to borrow USDC and transfer:

```solidity
// 1. Approve token and credit delegation
IERC20(WETH).approve(address(executor), amount);

// Approve credit delegation for borrowing
IPool pool = IPool(AAVE_V3_POOL);
DataTypes.ReserveData memory usdcReserve = pool.getReserveData(USDC);
ICreditDelegationToken(usdcReserve.variableDebtTokenAddress)
    .approveDelegation(address(executor), type(uint256).max);

// 2. Execute transfer (automatically supplies collateral and borrows USDC)
executor.executeTransfer(
    WETH,                    // collateral token
    destinationDomain,
    recipient,
    amount,                  // collateral amount
    maxFee
);
```

#### 3. Debt Management

Check and repay outstanding debt:

```solidity
// Check current debt
uint256 debt = executor.getUserBorrows(user);

// Repay debt
IERC20(USDC).approve(address(executor), debt);
executor.repayBorrowed(debt);
```

### Events

The contract emits `CrossChainTransferInitiated` events with the following information:
- User address
- Token address
- Supplied amount (0 for direct USDC transfers)
- Borrowed USDC amount
- Destination domain
- Recipient address
- Health factor after the operation

## Testing

Run the test suite:

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testExecuteTransfer_WhenTokenIsUSDC

# Run with gas report
forge test --gas-report
```

### Test Coverage

The test suite includes:

- Direct USDC cross-chain transfers
- WETH collateral-based borrows and transfers
- Debt tracking and repayment flows
- Integration tests on forked mainnet

### Running Tests on Fork

Tests use mainnet fork via `vm.createSelectFork()`. Ensure you have access to an Ethereum RPC endpoint or use a public node.

## Deployment

### Environment Setup

1. Create a `.env` file with the following variables:

```env
DEPLOYER_PRIVATE_KEY=your_private_key
ETHEREUM_SEPOLIA_POOL_ADDRESS=0x...
ETHEREUM_SEPOLIA_ORACLE_ADDRESS=0x...
ETHEREUM_SEPOLIA_TOKEN_MESSENGER_ADDRESS=0x...
ETHEREUM_SEPOLIA_USDC_ADDRESS=0x...
```

### Deploy Script

Deploy using Foundry scripts:

```bash

# Load environment variables
source .env

# Deploy CrossChainTransferExecutor
forge script script/DeployCrossChainTransferExecutor.s.sol:DeployCrossChainTransferExecutorScript \
    --rpc-url $ETHEREUM_SEPOLIA_RPC_URL \
    --broadcast \
    --verify -vvvv
```

## Security

### Security Features

- **Reentrancy Protection**: All external functions protected with `ReentrancyGuard`
- **Access Control**: Role-based permissions (Admin/Pauser)
- **Pausable**: Emergency pause functionality
- **Input Validation**: Comprehensive checks for zero addresses and amounts
- **Safe Token Operations**: Uses SafeERC20 for all token transfers
- **LTV Safety Buffer**: 95% of max borrowable amount to prevent liquidation

### Audit Status

⚠️ **This contract has not been audited. Use at your own risk.**

### Known Limitations

- Requires credit delegation approval from users for borrowing on their behalf
- Borrow amount limited by collateral LTV and safety buffer
- CCTP fees are deducted from transferred amount
- Interest accrues on borrowed USDC until repayment

## Technical Details

### Integrations

- **Aave V3**: For collateral supply and USDC borrowing
- **CCTP**: For cross-chain USDC transfers
- **OpenZeppelin**: For access control, pausable, and reentrancy protection

### Key Constants

- `MIN_FINALITY_THRESHOLD = 500`: Fast mode for CCTP
- `SAFETY_BUFFER_BPS = 9500`: 95% of max borrowable (prevents liquidation)
- `VARIABLE_RATE_MODE = 2`: Variable interest rate mode for Aave borrows

### Borrow Calculation

The maximum borrowable USDC is calculated as:

```
collateralValueUSD = (userCollateral * collateralPrice) / 10^collateralDecimals
borrowableUSD = (collateralValueUSD * LTV) / 10000
borrowableUSDC = (borrowableUSD * 10^usdcDecimals) / usdcPrice
safeBorrowAmount = (borrowableUSDC * 9500) / 10000  // 95% safety buffer
```

### Roles

- **DEFAULT_ADMIN_ROLE**: Full control, can grant/revoke other roles
- **ADMIN_ROLE**: Can grant/revoke pauser role
- **PAUSER_ROLE**: Can pause/unpause the contract

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please ensure:

1. All tests pass
2. Code follows the existing style
3. Security best practices are followed
4. Documentation is updated

## Resources

- [Foundry Documentation](https://book.getfoundry.sh/)
- [Aave V3 Documentation](https://docs.aave.com/)
- [CCTP Documentation](https://developers.circle.com/stablecoin/docs/cctp-technical-reference)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)

---

**⚠️ Disclaimer**: This software is provided "as is" without warranty. Use at your own risk.
