// SPDX-License-Identifier: AGPL-3.0-only
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.30;

import {ChainRegistry} from "./ChainRegistry.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title TokenRegistry
/// @notice This contract is used to register tokens and their destination chain keys
/// @dev This contract is used to register tokens and their destination chain keys
/// @dev Transfer accumulator is used to reduce the impact of a security incident
contract TokenRegistry is AccessManaged {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Enum representing the type of bridge for a token
    /// @dev MintBurn: Token is minted/burned on source/destination chain local to this contract
    /// @dev LockUnlock: Token is locked/unlocked on source/destination chain local to this contract
    enum BridgeTypeLocal {
        MintBurn,
        LockUnlock
    }

    /// @notice Struct to track transfer amounts within a time window
    /// @dev Used to implement transfer rate limiting for security
    /// @dev amount reset once windowStart + TRANSFER_ACCUMULATOR_WINDOW has passed
    /// @param amount The accumulated transfer amount in the current window
    /// @param windowStart The timestamp of the start of the current window
    struct TransferAccumulator {
        uint256 amount;
        uint256 windowStart;
    }

    /// @notice Time window for transfer accumulator (1 day)
    /// @dev Transfers are accumulated over this period to enforce rate limits
    uint256 public constant TRANSFER_ACCUMULATOR_WINDOW = 1 days;

    /// @dev Set of all registered token addresses
    EnumerableSet.AddressSet private _tokens;

    /// @dev Mapping from token address to set of destination chain keys
    mapping(address token => EnumerableSet.Bytes32Set chainKeys) private _destChainKeys;

    /// @dev Mapping from token address to destination chain key to destination chain token address
    mapping(address token => mapping(bytes32 chainKey => bytes32 tokenAddress)) private _destChainTokenAddresses;

    /// @dev Mapping from token address to destination chain key to destination chain decimals
    mapping(address token => mapping(bytes32 chainKey => uint256 decimals)) private _destChainTokenDecimals;

    /// @dev Mapping from token address to bridge type
    mapping(address token => BridgeTypeLocal bridgeType) private _bridgeType;

    /// @dev Mapping from token address to transfer accumulator data
    mapping(address token => TransferAccumulator transferAccumulator) private _transferAccumulator;

    /// @dev Mapping from token address to transfer accumulator cap
    mapping(address token => uint256 transferAccumulatorCap) private _transferAccumulatorCap;

    /// @notice Reference to the ChainRegistry contract
    /// @dev Used to validate destination chain keys
    ChainRegistry public immutable chainRegistry;

    /// @notice Thrown when a token is not registered
    /// @param token The unregistered token address
    error TokenNotRegistered(address token);

    /// @notice Thrown when a destination chain key is not registered for a token
    /// @param token The token address
    /// @param destChainKey The unregistered destination chain key
    error TokenDestChainKeyNotRegistered(address token, bytes32 destChainKey);

    /// @notice Thrown when a transfer would exceed the accumulator cap, both for outgoing and incoming transfers
    /// @param token The token address
    /// @param amount The attempted transfer amount
    /// @param currentAmount The current accumulated amount
    /// @param cap The transfer accumulator cap
    error OverTransferAccumulatorCap(address token, uint256 amount, uint256 currentAmount, uint256 cap);

    /// @notice Initializes the TokenRegistry contract
    /// @param initialAuthority The initial authority for access control
    /// @param _chainRegistry The ChainRegistry contract address
    constructor(address initialAuthority, ChainRegistry _chainRegistry) AccessManaged(initialAuthority) {
        chainRegistry = _chainRegistry;
    }

    /// @notice Adds a new token to the registry
    /// @dev Only callable by authorized addresses
    /// @param token The token address to register
    /// @param bridgeTypeLocal The bridge type for this token
    /// @param transferAccumulatorCap The maximum transfer amount per accumulator interval
    function addToken(address token, BridgeTypeLocal bridgeTypeLocal, uint256 transferAccumulatorCap)
        public
        restricted
    {
        _tokens.add(token);
        _bridgeType[token] = bridgeTypeLocal;
        _transferAccumulatorCap[token] = transferAccumulatorCap;
    }

    /// @notice Updates the transfer accumulator for a token
    /// @dev Only callable by authorized addresses
    /// @dev Resets accumulator if interval has passed, then adds the amount and updates the timestamp
    /// @param token The token address
    /// @param amount The amount to add to the accumulator
    function updateTokenTransferAccumulator(address token, uint256 amount) public restricted {
        TransferAccumulator memory transferAccumulator = _transferAccumulator[token];
        // reset accumulator and windowStart if interval has passed
        if (block.timestamp - transferAccumulator.windowStart >= TRANSFER_ACCUMULATOR_WINDOW) {
            transferAccumulator.amount = 0;
            transferAccumulator.windowStart = block.timestamp;
        }
        transferAccumulator.amount += amount;
        if (transferAccumulator.amount > _transferAccumulatorCap[token]) {
            revert OverTransferAccumulatorCap(token, amount, transferAccumulator.amount, _transferAccumulatorCap[token]);
        }
        _transferAccumulator[token] = transferAccumulator;
    }

    /// @notice Gets the transfer accumulator data for a token
    /// @param token The token address
    /// @return The transfer accumulator struct containing amount and timestamp
    function getTokenTransferAccumulator(address token) public view returns (TransferAccumulator memory) {
        return _transferAccumulator[token];
    }

    /// @notice Sets the bridge type for a token
    /// @dev Only callable by authorized addresses
    /// @param token The token address
    /// @param bridgeTypeLocal The new bridge type
    function setTokenBridgeType(address token, BridgeTypeLocal bridgeTypeLocal) public restricted {
        _bridgeType[token] = bridgeTypeLocal;
    }

    /// @notice Gets the bridge type for a token
    /// @param token The token address
    /// @return The bridge type for the token
    function getTokenBridgeType(address token) public view returns (BridgeTypeLocal) {
        return _bridgeType[token];
    }

    /// @notice Sets the transfer accumulator cap for a token
    /// @dev Only callable by authorized addresses
    /// @param token The token address
    /// @param transferAccumulatorCap The new transfer accumulator cap
    function setTokenTransferAccumulatorCap(address token, uint256 transferAccumulatorCap) public restricted {
        _transferAccumulatorCap[token] = transferAccumulatorCap;
    }

    /// @notice Gets the transfer accumulator cap for a token
    /// @param token The token address
    /// @return transferAccumulatorCap The transfer accumulator cap for the token
    function getTokenTransferAccumulatorCap(address token) public view returns (uint256 transferAccumulatorCap) {
        return _transferAccumulatorCap[token];
    }

    /// @notice Adds a destination chain key and token address for a token
    /// @dev Only callable by authorized addresses
    /// @dev Validates that the chain key is registered in ChainRegistry
    /// @param token The token address
    /// @param destChainKey The destination chain key to add
    /// @param destChainTokenAddress The token address on the destination chain (as bytes32)
    function addTokenDestChainKey(
        address token,
        bytes32 destChainKey,
        bytes32 destChainTokenAddress,
        uint256 destChainTokenDecimals
    ) public restricted {
        chainRegistry.revertIfChainKeyNotRegistered(destChainKey);
        _destChainKeys[token].add(destChainKey);
        _destChainTokenAddresses[token][destChainKey] = destChainTokenAddress;
        _destChainTokenDecimals[token][destChainKey] = destChainTokenDecimals;
    }

    /// @notice Removes a destination chain key for a token
    /// @dev Only callable by authorized addresses
    /// @param token The token address
    /// @param destChainKey The destination chain key to remove
    function removeTokenDestChainKey(address token, bytes32 destChainKey) public restricted {
        _destChainKeys[token].remove(destChainKey);
        delete _destChainTokenAddresses[token][destChainKey];
    }

    /// @notice Sets the destination chain token address for a token-chain pair
    /// @dev Only callable by authorized addresses
    /// @dev The chain key must already be registered for the token
    /// @param token The token address
    /// @param destChainKey The destination chain key
    /// @param destChainTokenAddress The token address on the destination chain (as bytes32)
    function setTokenDestChainTokenAddress(address token, bytes32 destChainKey, bytes32 destChainTokenAddress)
        public
        restricted
    {
        require(isTokenDestChainKeyRegistered(token, destChainKey), TokenDestChainKeyNotRegistered(token, destChainKey));
        _destChainTokenAddresses[token][destChainKey] = destChainTokenAddress;
    }

    /// @notice Gets the destination chain token address for a token-chain pair
    /// @param token The token address
    /// @param destChainKey The destination chain key
    /// @return destChainTokenAddress The token address on the destination chain (as bytes32)
    function getTokenDestChainTokenAddress(address token, bytes32 destChainKey)
        public
        view
        returns (bytes32 destChainTokenAddress)
    {
        return _destChainTokenAddresses[token][destChainKey];
    }

    /// @notice Gets all destination chain keys for a token
    /// @param token The token address
    /// @return items Array of destination chain keys
    function getTokenDestChainKeys(address token) public view returns (bytes32[] memory items) {
        return _destChainKeys[token].values();
    }

    /// @notice Gets the count of destination chain keys for a token
    /// @param token The token address
    /// @return count The number of destination chain keys
    function getTokenDestChainKeyCount(address token) public view returns (uint256 count) {
        return _destChainKeys[token].length();
    }

    /// @notice Gets a destination chain key at a specific index for a token
    /// @param token The token address
    /// @param index The index of the destination chain key
    /// @return item The destination chain key at the specified index
    function getTokenDestChainKeyAt(address token, uint256 index) public view returns (bytes32 item) {
        return _destChainKeys[token].at(index);
    }

    /// @notice Gets a range of destination chain keys for a token
    /// @param token The token address
    /// @param index The starting index
    /// @param count The number of items to retrieve
    /// @return items Array of destination chain keys
    function getTokenDestChainKeysFrom(address token, uint256 index, uint256 count)
        public
        view
        returns (bytes32[] memory items)
    {
        uint256 totalLength = _destChainKeys[token].length();
        if (index >= totalLength) {
            return new bytes32[](0);
        }
        if (index + count > totalLength) {
            count = totalLength - index;
        }
        items = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            items[i] = _destChainKeys[token].at(index + i);
        }
    }

    /// @notice Gets destination chain keys and their corresponding token addresses for a token
    /// @param token The token address
    /// @return chainKeys Array of destination chain keys
    /// @return tokenAddresses Array of corresponding token addresses on destination chains
    function getTokenDestChainKeysAndTokenAddresses(address token)
        public
        view
        returns (bytes32[] memory chainKeys, bytes32[] memory tokenAddresses)
    {
        chainKeys = _destChainKeys[token].values();
        tokenAddresses = new bytes32[](chainKeys.length);
        for (uint256 i = 0; i < chainKeys.length; i++) {
            tokenAddresses[i] = _destChainTokenAddresses[token][chainKeys[i]];
        }
    }

    /// @notice Checks if a destination chain key is registered for a token
    /// @param token The token address
    /// @param destChainKey The destination chain key to check
    /// @return True if the destination chain key is registered, false otherwise
    function isTokenDestChainKeyRegistered(address token, bytes32 destChainKey) public view returns (bool) {
        return _destChainKeys[token].contains(destChainKey);
    }

    /// @notice Gets the total count of registered tokens
    /// @return The number of registered tokens
    function getTokenCount() public view returns (uint256) {
        return _tokens.length();
    }

    /// @notice Gets a token at a specific index
    /// @param index The index of the token
    /// @return The token address at the specified index
    function getTokenAt(uint256 index) public view returns (address) {
        return _tokens.at(index);
    }

    /// @notice Gets all registered tokens
    /// @return Array of all registered token addresses
    function getAllTokens() public view returns (address[] memory) {
        return _tokens.values();
    }

    /// @notice Gets a range of registered tokens
    /// @param index The starting index
    /// @param count The number of items to retrieve
    /// @return items Array of token addresses
    function getTokensFrom(uint256 index, uint256 count) public view returns (address[] memory items) {
        uint256 totalLength = _tokens.length();
        if (index >= totalLength) {
            return new address[](0);
        }
        if (index + count > totalLength) {
            count = totalLength - index;
        }
        items = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            items[i] = _tokens.at(index + i);
        }
    }

    /// @notice Checks if a token is registered
    /// @param token The token address to check
    /// @return True if the token is registered, false otherwise
    function isTokenRegistered(address token) public view returns (bool) {
        return _tokens.contains(token);
    }

    /// @notice Reverts if a token is not registered
    /// @dev Used for validation in other functions
    /// @param token The token address to check
    function revertIfTokenNotRegistered(address token) public view {
        require(isTokenRegistered(token), TokenNotRegistered(token));
    }

    /// @notice Reverts if a token-destination chain key pair is not registered
    /// @dev Validates both token registration and destination chain key registration
    /// @param token The token address
    /// @param destChainKey The destination chain key
    function revertIfTokenDestChainKeyNotRegistered(address token, bytes32 destChainKey) public view {
        chainRegistry.revertIfChainKeyNotRegistered(destChainKey);
        revertIfTokenNotRegistered(token);
        require(isTokenDestChainKeyRegistered(token, destChainKey), TokenDestChainKeyNotRegistered(token, destChainKey));
    }

    /// @notice Reverts if a transfer would exceed the accumulator cap
    /// @dev Checks if the transfer amount would exceed the rate limit
    /// @param token The token address
    /// @param amount The transfer amount to check
    function revertIfOverTransferAccumulatorCap(address token, uint256 amount) public view {
        TransferAccumulator memory transferAccumulator = _transferAccumulator[token];
        uint256 transferAccumulatorCap = _transferAccumulatorCap[token];
        bool isInAccumulatorInterval = block.timestamp - transferAccumulator.windowStart < TRANSFER_ACCUMULATOR_WINDOW;
        uint256 currentAmount = isInAccumulatorInterval ? transferAccumulator.amount + amount : amount;
        if (currentAmount > transferAccumulatorCap) {
            revert OverTransferAccumulatorCap(token, amount, transferAccumulator.amount, transferAccumulatorCap);
        }
    }
}
