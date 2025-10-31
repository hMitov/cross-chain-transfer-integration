// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ICrossChainTransferExecutor
 * @notice Interface for the CrossChainTransferExecutor contract
 */
interface ICrossChainTransferExecutor {
    // Errors
    /// @notice Emitted when a zero address is not allowed
    error ZeroAddressNotAllowed();
    /// @notice Emitted when a zero amount is not allowed
    error ZeroAmountNotAllowed();
    /// @notice Emitted when a fee is too high
    error FeeTooHigh();
    /// @notice Emitted when the caller is not an admin
    error CallerIsNotAdmin();
    /// @notice Emitted when the caller is not a pauser
    error CallerIsNotPauser();

    // Events
    /// @notice Emitted when a cross-chain transfer is initiated
    event CrossChainTransferInitiated(
        address indexed user,
        address indexed token,
        uint256 suppliedAmount,
        uint256 borrowedUsdc,
        uint32 destinationDomain,
        address recipient,
        uint256 healthFactor
    );

    /**
     * @notice Executes a cross-chain transfer
     * @param token The address of the token being transferred
     * @param destinationDomain The domain of the destination chain
     * @param recipientAddress The address of the recipient on the destination chain
     * @param amount The amount of the token being transferred
     * @param maxFee The maximum fee to pay for the transfer
     */
    function executeTransfer(
        address token,
        uint32 destinationDomain,
        address recipientAddress,
        uint256 amount,
        uint256 maxFee
    ) external;

    /**
     * @notice Gets the user's total debt in USDC
     * @param user The address of the user
     * @return totalDebtUsdc The user's total debt in USDC
     */
    function getUserBorrows(address user) external view returns (uint256 totalDebtUsdc);

    /**
     * @notice Repays the user's debt in USDC
     * @param amount The amount of USDC to repay
     */
    function repayBorrowed(uint256 amount) external;
}
