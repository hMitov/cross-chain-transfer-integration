// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAaveOracle} from "@aave/core-v3/contracts/interfaces/IAaveOracle.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave/core-v3/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {IERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {IERC20Detailed} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {SafeERC20} from "@aave/core-v3/contracts/dependencies/openzeppelin/contracts/SafeERC20.sol";
import {ITokenMessenger} from "./interfaces/ITokenMessenger.sol";
import {ICrossChainTransferExecutor} from "./interfaces/ICrossChainTransferExecutor.sol";

/**
 * @title CrossChainTransferExecutor
 * @notice Executes a cross-chain transfer of tokens between Aave V3 and CCTP
 * @dev This contract is used to execute a cross-chain transfer of tokens between Aave V3 and CCTP
 *      It is used to transfer USDC across chain and to borrow USDC on behalf of a user when the token is not USDC.
 */
contract CrossChainTransferExecutor is ICrossChainTransferExecutor, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    IPool public immutable POOL;
    IAaveOracle public immutable ORACLE;
    ITokenMessenger public immutable TOKEN_MESSENGER;
    address public immutable USDC;

    uint32 private constant MIN_FINALITY_THRESHOLD = 500; // fast mode
    uint256 private constant SAFETY_BUFFER_BPS = 9500; // 95%
    uint256 private constant BPS_DENOM = 10_000;
    uint256 private constant VARIABLE_RATE_MODE = 2;

    /// @notice Role for administrative functions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role for pausing/unpausing operations
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor(address _pool, address _oracle, address _tokenMessenger, address _usdc) {
        if (_pool == address(0)) revert ZeroAddressNotAllowed();
        if (_oracle == address(0)) revert ZeroAddressNotAllowed();
        if (_tokenMessenger == address(0)) revert ZeroAddressNotAllowed();
        if (_usdc == address(0)) revert ZeroAddressNotAllowed();

        POOL = IPool(_pool);
        ORACLE = IAaveOracle(_oracle);
        TOKEN_MESSENGER = ITokenMessenger(_tokenMessenger);
        USDC = _usdc;

        address deployer = msg.sender;

        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(ADMIN_ROLE, deployer);
        _grantRole(PAUSER_ROLE, deployer);

        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
    }

    /// @notice Modifier to restrict access to admin functions
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    /// @notice Internal function to restrict access to admin functions
    function _onlyAdmin() internal view {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert CallerIsNotAdmin();
    }

    /// @notice Modifier to restrict access to pauser functions
    modifier onlyPauser() {
        _onlyPauser();
        _;
    }

    /// @notice Internal function to restrict access to pauser functions
    function _onlyPauser() internal view {
        if (!hasRole(PAUSER_ROLE, msg.sender)) revert CallerIsNotPauser();
    }

    /**
     * @notice Pause all operations
     * @dev Only callable by pauser role
     */
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * @notice Unpause all operations
     * @dev Only callable by pauser role
     */
    function unpause() external onlyPauser {
        _unpause();
    }

    /**
     * @notice Grant pauser role to an account
     * @param account The account to grant the role to
     * @dev Only callable by admin role
     */
    function grantPauserRole(address account) external onlyAdmin {
        if (account == address(0)) revert ZeroAddressNotAllowed();
        grantRole(PAUSER_ROLE, account);
    }

    /**
     * @notice Revoke pauser role from an account
     * @param account The account to revoke the role from
     * @dev Only callable by admin role
     */
    function revokePauserRole(address account) external onlyAdmin {
        if (account == address(0)) revert ZeroAddressNotAllowed();
        revokeRole(PAUSER_ROLE, account);
    }

    /**
     * @notice Executes a cross-chain transfer
     * @param token The address of the token being transferred
     * @param destinationDomain The domain of the destination chain
     * @param recipient The address of the recipient on the destination chain
     * @param amount The amount of the token being transferred
     * @param maxFee The maximum fee to pay for the transfer
     */
    function executeTransfer(
        address token,
        uint32 destinationDomain,
        address recipient,
        uint256 amount,
        uint256 maxFee
    ) external nonReentrant whenNotPaused {
        if (token == address(0)) revert ZeroAddressNotAllowed();
        if (recipient == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert ZeroAmountNotAllowed();
        if (maxFee >= amount) revert FeeTooHigh();

        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);

        uint256 borrowedUsdc = 0;
        if (token == USDC) {
            _cctpTransfer(destinationDomain, recipient, amount, maxFee);
        } else {
            // Supply collateral on behalf of user
            SafeERC20.safeApprove(IERC20(token), address(POOL), amount);
            POOL.supply(token, amount, msg.sender, 0);
            SafeERC20.safeApprove(IERC20(token), address(POOL), 0);

            // Compute safe borrow amount
            borrowedUsdc = _maxBorrowableUsdc(msg.sender, token);

            // Borrow on behalf of user
            POOL.borrow(USDC, borrowedUsdc, VARIABLE_RATE_MODE, 0, msg.sender);

            // Send across chain
            _cctpTransfer(destinationDomain, recipient, borrowedUsdc, maxFee);
        }

        (,,,,, uint256 hf) = POOL.getUserAccountData(msg.sender);

        emit CrossChainTransferInitiated(
            msg.sender, token, token == USDC ? 0 : amount, borrowedUsdc, destinationDomain, recipient, hf
        );
    }

    /**
     * @notice Transfers USDC across chain
     * @param destinationDomain The domain of the destination chain
     * @param recipient The address of the recipient on the destination chain
     * @param amount The amount of USDC to transfer
     * @param maxFee The maximum fee to pay for the transfer
     */
    function _cctpTransfer(uint32 destinationDomain, address recipient, uint256 amount, uint256 maxFee) internal {
        bytes32 mintRecipient = bytes32(uint256(uint160(recipient)));
        SafeERC20.safeApprove(IERC20(USDC), address(TOKEN_MESSENGER), amount);
        TOKEN_MESSENGER.depositForBurn(
            amount, destinationDomain, mintRecipient, USDC, bytes32(0), maxFee, MIN_FINALITY_THRESHOLD
        );
        SafeERC20.safeApprove(IERC20(USDC), address(TOKEN_MESSENGER), 0);
    }

    /**
     * @notice Computes the maximum borrowable amount of USDC
     * @param user The address of the user
     * @param collateral The address of the collateral
     * @return borrowableUsdc The maximum borrowable amount of USDC
     */
    function _maxBorrowableUsdc(address user, address collateral) internal view returns (uint256) {
        DataTypes.ReserveConfigurationMap memory cfg = POOL.getConfiguration(collateral);
        uint256 ltvBps = cfg.getLtv();

        DataTypes.ReserveData memory rdata = POOL.getReserveData(collateral);
        address aToken = rdata.aTokenAddress;
        uint256 userCollateral = IERC20(aToken).balanceOf(user);

        uint256 collPrice = ORACLE.getAssetPrice(collateral);
        uint256 usdcPrice = ORACLE.getAssetPrice(USDC);
        uint8 collDec = IERC20Detailed(collateral).decimals();
        uint8 usdcDec = IERC20Detailed(USDC).decimals();

        // USD value of collateral * LTV
        uint256 collateralValueUsd = (userCollateral * collPrice) / (10 ** collDec);
        uint256 borrowableUsd = (collateralValueUsd * ltvBps) / BPS_DENOM;
        uint256 borrowableUsdc = (borrowableUsd * (10 ** usdcDec)) / usdcPrice;

        return (borrowableUsdc * SAFETY_BUFFER_BPS) / BPS_DENOM;
    }

    /**
     * @notice Gets the user's total debt in USDC
     * @param user The address of the user
     * @return totalDebtUsdc The user's total debt in USDC
     */
    function getUserBorrows(address user) external view whenNotPaused returns (uint256 totalDebtUsdc) {
        if (user == address(0)) revert ZeroAddressNotAllowed();

        DataTypes.ReserveData memory rdata = POOL.getReserveData(USDC);
        uint256 varDebt = IERC20(rdata.variableDebtTokenAddress).balanceOf(user);
        uint256 stableDebt = 0;
        if (rdata.stableDebtTokenAddress != address(0)) {
            (bool ok, bytes memory data) =
                rdata.stableDebtTokenAddress.staticcall(abi.encodeWithSignature("balanceOf(address)", user));
            if (ok && data.length >= 32) {
                stableDebt = abi.decode(data, (uint256));
            }
        }
        totalDebtUsdc = varDebt + stableDebt;
    }

    /**
     * @notice Repays the user's debt in USDC
     * @param amount The amount of USDC to repay
     */
    function repayBorrowed(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmountNotAllowed();

        SafeERC20.safeTransferFrom(IERC20(USDC), msg.sender, address(this), amount);
        SafeERC20.safeApprove(IERC20(USDC), address(POOL), amount);
        POOL.repay(USDC, amount, VARIABLE_RATE_MODE, msg.sender);
        SafeERC20.safeApprove(IERC20(USDC), address(POOL), 0);
    }
}
