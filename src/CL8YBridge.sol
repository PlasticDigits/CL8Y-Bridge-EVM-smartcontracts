// SPDX-License-Identifier: AGPL-3.0-only
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {TokenRegistry} from "./TokenRegistry.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {MintBurn} from "./MintBurn.sol";
import {LockUnlock} from "./LockUnlock.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CL8Y Bridge
/// @notice Cross-chain bridge contract for transferring tokens between different blockchains
/// @dev This contract handles deposits and withdrawals using either mint/burn or lock/unlock mechanisms
/// @dev Supports access control through AccessManaged and prevents duplicate withdrawals
contract Cl8YBridge is AccessManaged, Pausable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Withdraw request structure
    /// @dev Contains all necessary information for processing a withdrawal
    struct Withdraw {
        /// @notice The source chain key where the deposit originated
        bytes32 srcChainKey;
        /// @notice The token address on the destination chain (local token address)
        address token;
        /// @notice The recipient address for the withdrawal
        address to;
        /// @notice The amount of tokens to withdraw
        uint256 amount;
        /// @notice Unique nonce for this withdrawal request
        uint256 nonce;
    }

    /// @notice Deposit request structure
    /// @dev Contains all necessary information for processing a deposit
    struct Deposit {
        /// @notice The destination chain key where tokens will be withdrawn
        bytes32 destChainKey;
        /// @notice The token address on the destination chain
        bytes32 destTokenAddress;
        /// @notice The destination account address
        bytes32 destAccount;
        /// @notice The sender address making the deposit
        address from;
        /// @notice The amount of tokens to deposit
        uint256 amount;
        /// @notice Unique nonce for this deposit request
        uint256 nonce;
    }

    /// @dev Set of all withdraw hashes to aid off-chain indexing
    EnumerableSet.Bytes32Set private _withdrawHashes;

    /// @dev Set of all deposit hashes for tracking processed deposits
    EnumerableSet.Bytes32Set private _depositHashes;

    /// @notice Current deposit nonce counter
    /// @dev Incremented for each deposit to ensure uniqueness
    uint256 public depositNonce = 0;

    /// @dev Mapping from withdraw hash to withdraw request details
    mapping(bytes32 withdrawHash => Withdraw withdraw) private _withdraws;

    /// @dev Mapping from deposit hash to deposit request details
    mapping(bytes32 depositHash => Deposit deposit) private _deposits;

    /// @notice MintBurn contract instance for handling mint/burn operations
    /// @dev Immutable reference set during construction
    MintBurn public immutable mintBurn;

    /// @notice LockUnlock contract instance for handling lock/unlock operations
    /// @dev Immutable reference set during construction
    LockUnlock public immutable lockUnlock;

    /// @notice Reference to the TokenRegistry contract
    /// @dev Used to validate destination chain keys and manage token configurations
    TokenRegistry public immutable tokenRegistry;

    /// @notice Errors
    error WithdrawNotApproved();
    error ApprovalCancelled();
    error ApprovalExecuted();
    error IncorrectFeeValue();
    error NoFeeViaMsgValueWhenDeductFromAmount();
    error FeeRecipientZero();
    error FeeTransferFailed();
    error NonceAlreadyApproved(bytes32 srcChainKey, uint256 nonce);
    error NotCancelled();

    /// @notice Emitted when a deposit request is created
    /// @param destChainKey The destination chain key
    /// @param destTokenAddress The token address on the destination chain
    /// @param destAccount The destination account address
    /// @param token The token address being deposited (local)
    /// @param amount The amount of tokens being deposited
    /// @param nonce The unique nonce for this deposit
    event DepositRequest(
        bytes32 indexed destChainKey,
        bytes32 indexed destTokenAddress,
        bytes32 indexed destAccount,
        address token,
        uint256 amount,
        uint256 nonce
    );

    /// @notice Emitted when a withdrawal request is processed
    /// @param srcChainKey The source chain key
    /// @param token The token address being withdrawn
    /// @param to The recipient address
    /// @param amount The amount of tokens being withdrawn
    /// @param nonce The unique nonce for this withdrawal
    event WithdrawRequest(
        bytes32 indexed srcChainKey, address indexed token, address indexed to, uint256 amount, uint256 nonce
    );

    /// @notice Approval metadata for a withdrawal
    struct WithdrawApproval {
        uint256 fee; // native currency fee to be paid
        address feeRecipient; // recipient of the fee
        bool isApproved; // true if approval was created
        bool deductFromAmount; // if true, fee is deducted from withdrawal proceeds (native path)
        bool cancelled; // true if approval was cancelled
        bool executed; // true if approval was consumed by a withdrawal
    }

    /// @dev Mapping from withdraw hash to approval data
    mapping(bytes32 withdrawHash => WithdrawApproval approval) private _withdrawApprovals;

    /// @dev Tracks nonce usage per source chain key to prevent duplicate approvals for the same nonce
    mapping(bytes32 srcChainKey => mapping(uint256 nonce => bool used)) private _withdrawNonceUsed;

    /// @notice Emitted when a withdrawal is approved by an operator
    event WithdrawApproved(
        bytes32 indexed withdrawHash,
        bytes32 indexed srcChainKey,
        address indexed token,
        address to,
        uint256 amount,
        uint256 nonce,
        uint256 fee,
        address feeRecipient,
        bool deductFromAmount
    );

    /// @notice Emitted when an approval is cancelled
    event WithdrawApprovalCancelled(bytes32 indexed withdrawHash);

    /// @notice Emitted when an approval is reenabled
    event WithdrawApprovalReenabled(bytes32 indexed withdrawHash);

    /// @notice Emitted when a withdrawal executes with a fee
    event WithdrawExecutedWithFee(
        bytes32 indexed withdrawHash, uint256 fee, address feeRecipient, bool feeDeductedFromAmount
    );

    /// @notice Initializes the CL8Y Bridge contract
    /// @param initialAuthority The initial authority address for access control
    /// @param _tokenRegistry The TokenRegistry contract address
    /// @param _mintBurn The MintBurn contract address
    /// @param _lockUnlock The LockUnlock contract address
    constructor(address initialAuthority, TokenRegistry _tokenRegistry, MintBurn _mintBurn, LockUnlock _lockUnlock)
        AccessManaged(initialAuthority)
    {
        tokenRegistry = _tokenRegistry;
        mintBurn = _mintBurn;
        lockUnlock = _lockUnlock;
    }

    /// @notice Deposits tokens to be bridged to another chain
    /// @dev Restricted: only callers granted by `AccessManager` may invoke this function.
    /// @dev Validates the destination chain and updates transfer accumulator.
    /// @dev Uses either mint/burn or lock/unlock mechanism based on token configuration.
    /// @param payer The address whose tokens will be burned/locked
    /// @param destChainKey The destination chain key
    /// @param destAccount The destination account address (chain-specific format encoded as bytes32)
    /// @param token The token address to deposit
    /// @param amount The amount of tokens to deposit
    function deposit(address payer, bytes32 destChainKey, bytes32 destAccount, address token, uint256 amount)
        public
        whenNotPaused
        restricted
        nonReentrant
    {
        tokenRegistry.revertIfTokenDestChainKeyNotRegistered(token, destChainKey);

        Deposit memory depositRequest = Deposit({
            destChainKey: destChainKey,
            destTokenAddress: tokenRegistry.getTokenDestChainTokenAddress(token, destChainKey),
            destAccount: destAccount,
            from: payer,
            amount: amount,
            nonce: depositNonce
        });

        // Since the nonce is incremented after the deposit request is created,
        // the deposit request is guaranteed to be unique: Duplicate deposits are not possible
        bytes32 depositHash = getDepositHash(depositRequest);

        _depositHashes.add(depositHash);
        _deposits[depositHash] = depositRequest;

        emit DepositRequest(destChainKey, depositRequest.destTokenAddress, destAccount, token, amount, depositNonce);
        depositNonce++;

        // Rate limit checks and accounting are enforced by guard modules via the router

        // mintBurn and lockUnlock both prevent reentrancy attacks
        if (tokenRegistry.getTokenBridgeType(token) == TokenRegistry.BridgeTypeLocal.MintBurn) {
            mintBurn.burn(payer, token, amount);
        } else if (tokenRegistry.getTokenBridgeType(token) == TokenRegistry.BridgeTypeLocal.LockUnlock) {
            lockUnlock.lock(payer, token, amount);
        }
    }

    /// @notice Processes a withdrawal request from another chain
    /// @dev Restricted: only callers granted by `AccessManager` may invoke this function.
    /// @dev Prevents duplicate withdrawals using hash-based tracking
    /// @param srcChainKey The source chain key where the deposit originated
    /// @param token The token address on this chain
    /// @param to The recipient address
    /// @param amount The amount of tokens to withdraw
    /// @param nonce The unique nonce for this withdrawal
    function withdraw(bytes32 srcChainKey, address token, address to, uint256 amount, uint256 nonce)
        public
        payable
        restricted
        whenNotPaused
        nonReentrant
    {
        tokenRegistry.revertIfTokenDestChainKeyNotRegistered(token, srcChainKey);

        Withdraw memory withdrawRequest =
            Withdraw({srcChainKey: srcChainKey, token: token, to: to, amount: amount, nonce: nonce});

        bytes32 withdrawHash = getWithdrawHash(withdrawRequest);

        // Enforce approval lifecycle first (ensures these branches are observable)
        WithdrawApproval memory approval = _withdrawApprovals[withdrawHash];
        if (!approval.isApproved) revert WithdrawNotApproved();
        if (approval.cancelled) revert ApprovalCancelled();
        if (approval.executed) revert ApprovalExecuted();

        // Fee handling
        if (approval.deductFromAmount) {
            // Native path: fee is deducted off-chain (router unwrap/distribution). No ETH should be sent here.
            if (msg.value != 0) revert NoFeeViaMsgValueWhenDeductFromAmount();
        } else {
            if (msg.value < approval.fee) revert IncorrectFeeValue();
            // If any native value is sent (fee or overpayment), feeRecipient must be set
            if (msg.value > 0 && approval.feeRecipient == address(0)) revert FeeRecipientZero();
        }

        // Mark executed before any external effects to prevent replay
        _withdrawApprovals[withdrawHash].executed = true;

        _withdrawHashes.add(withdrawHash);
        _withdraws[withdrawHash] = withdrawRequest;

        // Rate limit checks and accounting are enforced by guard modules via the router

        if (tokenRegistry.getTokenBridgeType(token) == TokenRegistry.BridgeTypeLocal.MintBurn) {
            mintBurn.mint(to, token, amount);
        } else if (tokenRegistry.getTokenBridgeType(token) == TokenRegistry.BridgeTypeLocal.LockUnlock) {
            lockUnlock.unlock(to, token, amount);
        }

        // Perform native value transfer to feeRecipient at the very end if applicable
        if (!approval.deductFromAmount && msg.value > 0) {
            (bool ok,) = payable(approval.feeRecipient).call{value: msg.value}("");
            if (!ok) revert FeeTransferFailed();
        }

        emit WithdrawRequest(srcChainKey, token, to, amount, nonce);
        emit WithdrawExecutedWithFee(withdrawHash, approval.fee, approval.feeRecipient, approval.deductFromAmount);
    }

    /// @notice Generates a unique hash for a withdrawal request
    /// @dev Used to prevent duplicate withdrawals
    /// @param withdrawRequest The withdrawal request to hash
    /// @return withdrawHash The keccak256 hash of the withdrawal request
    function getWithdrawHash(Withdraw memory withdrawRequest) public pure returns (bytes32 withdrawHash) {
        return keccak256(abi.encode(withdrawRequest));
    }

    /// @notice Generates a unique hash for a deposit request
    /// @dev Used for tracking and verification purposes
    /// @param depositRequest The deposit request to hash
    /// @return depositHash The keccak256 hash of the deposit request
    function getDepositHash(Deposit memory depositRequest) public pure returns (bytes32 depositHash) {
        return keccak256(abi.encode(depositRequest));
    }

    /// @notice Pauses deposit and withdraw functionality
    /// @dev Restricted: only callers granted by `AccessManager` may invoke this function.
    function pause() public restricted {
        _pause();
    }

    /// @notice Unpauses deposit and withdraw functionality
    /// @dev Restricted: only callers granted by `AccessManager` may invoke this function.
    function unpause() public restricted {
        _unpause();
    }

    /// @notice Returns a slice of recorded deposit hashes
    /// @param index Starting index in the internal set
    /// @param count Maximum number of items to return
    /// @return hashes Array of deposit hashes
    function getDepositHashes(uint256 index, uint256 count) public view returns (bytes32[] memory hashes) {
        uint256 totalLength = _depositHashes.length();
        if (index >= totalLength) {
            return new bytes32[](0);
        }
        if (index + count > totalLength) {
            count = totalLength - index;
        }
        hashes = new bytes32[](count);
        for (uint256 i; i < count; i++) {
            hashes[i] = _depositHashes.at(index + i);
        }
    }

    /// @notice Returns a slice of recorded withdraw hashes to aid off-chain indexing
    /// @param index Starting index in the internal set
    /// @param count Maximum number of items to return
    /// @return hashes Array of withdraw hashes
    function getWithdrawHashes(uint256 index, uint256 count) public view returns (bytes32[] memory hashes) {
        uint256 totalLength = _withdrawHashes.length();
        if (index >= totalLength) {
            return new bytes32[](0);
        }
        if (index + count > totalLength) {
            count = totalLength - index;
        }
        hashes = new bytes32[](count);
        for (uint256 i; i < count; i++) {
            hashes[i] = _withdrawHashes.at(index + i);
        }
    }

    /// @notice Retrieves a stored `Deposit` by its hash
    /// @param depositHash The deposit hash as returned by `getDepositHash`
    /// @return deposit_ The stored `Deposit` struct
    function getDepositFromHash(bytes32 depositHash) public view returns (Deposit memory deposit_) {
        return _deposits[depositHash];
    }

    /// @notice Retrieves a stored `Withdraw` by its hash
    /// @param withdrawHash The withdraw hash as returned by `getWithdrawHash`
    /// @return withdraw_ The stored `Withdraw` struct
    function getWithdrawFromHash(bytes32 withdrawHash) public view returns (Withdraw memory withdraw_) {
        return _withdraws[withdrawHash];
    }

    /// @notice Get approval info for a given withdraw hash
    function getWithdrawApproval(bytes32 withdrawHash) public view returns (WithdrawApproval memory approval) {
        return _withdrawApprovals[withdrawHash];
    }

    /// @notice Approve a withdrawal with fee terms
    function approveWithdraw(
        bytes32 srcChainKey,
        address token,
        address to,
        uint256 amount,
        uint256 nonce,
        uint256 fee,
        address feeRecipient,
        bool deductFromAmount
    ) public restricted whenNotPaused {
        Withdraw memory withdrawRequest =
            Withdraw({srcChainKey: srcChainKey, token: token, to: to, amount: amount, nonce: nonce});
        bytes32 withdrawHash = getWithdrawHash(withdrawRequest);
        // Enforce per-srcChainKey nonce uniqueness across all approvals
        if (_withdrawNonceUsed[srcChainKey][nonce]) revert NonceAlreadyApproved(srcChainKey, nonce);

        // Cannot override an active approval
        WithdrawApproval memory existing = _withdrawApprovals[withdrawHash];
        if (existing.executed) revert ApprovalExecuted();
        if (existing.cancelled) revert ApprovalCancelled();

        // If any fee is configured, a recipient must be provided
        if (fee > 0 && feeRecipient == address(0)) revert FeeRecipientZero();

        _withdrawApprovals[withdrawHash] = WithdrawApproval({
            fee: fee,
            feeRecipient: feeRecipient,
            isApproved: true,
            deductFromAmount: deductFromAmount,
            cancelled: false,
            executed: false
        });

        _withdrawNonceUsed[srcChainKey][nonce] = true;

        emit WithdrawApproved(withdrawHash, srcChainKey, token, to, amount, nonce, fee, feeRecipient, deductFromAmount);
    }

    /// @notice Cancel a previously approved withdrawal
    function cancelWithdrawApproval(bytes32 srcChainKey, address token, address to, uint256 amount, uint256 nonce)
        public
        restricted
        whenNotPaused
    {
        Withdraw memory withdrawRequest =
            Withdraw({srcChainKey: srcChainKey, token: token, to: to, amount: amount, nonce: nonce});
        bytes32 withdrawHash = getWithdrawHash(withdrawRequest);
        WithdrawApproval storage approval = _withdrawApprovals[withdrawHash];
        if (approval.cancelled) revert ApprovalCancelled();
        if (approval.executed) revert ApprovalExecuted();

        approval.cancelled = true;
        emit WithdrawApprovalCancelled(withdrawHash);
    }

    // @notice reenable a cancelled approval
    function reenableWithdrawApproval(bytes32 srcChainKey, address token, address to, uint256 amount, uint256 nonce)
        public
        restricted
        whenNotPaused
    {
        Withdraw memory withdrawRequest =
            Withdraw({srcChainKey: srcChainKey, token: token, to: to, amount: amount, nonce: nonce});
        bytes32 withdrawHash = getWithdrawHash(withdrawRequest);
        WithdrawApproval storage approval = _withdrawApprovals[withdrawHash];
        if (!approval.cancelled) revert NotCancelled();
        if (approval.executed) revert ApprovalExecuted();

        approval.cancelled = false;
        emit WithdrawApprovalReenabled(withdrawHash);
    }
}
