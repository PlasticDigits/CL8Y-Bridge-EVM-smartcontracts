// SPDX-License-Identifier: GPL-3.0
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {TokenCl8yBridged} from "./TokenCl8yBridged.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract FactoryTokenCl8yBridged is AccessManaged {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.AddressSet private _tokens;

    string private constant NAME_SUFFIX = " cl8y.com/bridge";
    string private constant SYMBOL_SUFFIX = "-cb";
    uint256 private immutable DEPLOYED_CHAIN_ID = block.chainid;

    string public logoLink;

    mapping(address token => mapping(string chainType => EnumerableSet.UintSet chainIds)) private _tokenChainIds;

    constructor(address initialAuthority) AccessManaged(initialAuthority) {}

    /// @notice Create a new token
    /// @param baseName The base name of the token
    /// @param baseSymbol The base symbol of the token
    /// @param originChainId The chain ID where the token was originally minted
    /// @param originChainType The type of the origin chain (e.g. "EVM", "CosmWasm", "Sol", etc.)
    /// @param _logoLink The link to the token's logo (can be ipfs:// or https://)
    function createToken(
        string memory baseName,
        string memory baseSymbol,
        uint256 originChainId,
        string memory originChainType,
        string memory _logoLink
    ) public restricted returns (address) {
        address token = address(
            new TokenCl8yBridged{
                salt: keccak256(abi.encode(baseName, baseSymbol, originChainId, originChainType, msg.sender))
            }(
                string.concat(baseName, NAME_SUFFIX),
                string.concat(baseSymbol, SYMBOL_SUFFIX),
                authority(),
                originChainId,
                originChainType,
                _logoLink
            )
        );
        _tokens.add(token);
        _tokenChainIds[token][originChainType].add(originChainId);
        logoLink = _logoLink;
        return token;
    }

    /// @notice Get all created tokens
    function getAllTokens() public view returns (address[] memory) {
        return _tokens.values();
    }

    /// @notice Get the number of created tokens
    function getTokensCount() public view returns (uint256) {
        return _tokens.length();
    }

    /// @notice Get a token at a given index
    function getTokenAt(uint256 index) public view returns (address) {
        return _tokens.at(index);
    }

    /// @notice Get created tokens, paginated
    function getTokensFrom(uint256 index, uint256 count) public view returns (address[] memory items) {
        uint256 totalLength = _tokens.length();
        if (index >= totalLength) {
            return new address[](0);
        }
        if (index + count > totalLength) {
            count = totalLength - index;
        }
        items = new address[](count);
        for (uint256 i; i < count; i++) {
            items[i] = _tokens.at(index + i);
        }
        return items;
    }

    /// @notice Check if a token was created by this factory
    function isTokenCreated(address token) public view returns (bool) {
        return _tokens.contains(token);
    }

    /// @notice Get the chain IDs for a token
    /// @param token The address of the token
    /// @param chainType The type of the chain (e.g. "EVM", "COSMW", "SOL", etc.)
    /// @return The chain IDs for the token
    function getAllTokenChainIdsForType(address token, string memory chainType)
        public
        view
        returns (uint256[] memory)
    {
        return _tokenChainIds[token][chainType].values();
    }

    /// @notice Get the number of chain IDs for a token
    /// @param token The address of the token
    /// @param chainType The type of the chain (e.g. "EVM", "COSMW", "SOL", etc.)
    /// @return The number of chain IDs for the token
    function getTokenChainIdsForTypeCount(address token, string memory chainType) public view returns (uint256) {
        return _tokenChainIds[token][chainType].length();
    }

    /// @notice Get the chain ID for a token at a given index
    /// @param token The address of the token
    /// @param chainType The type of the chain (e.g. "EVM", "COSMW", "SOL", etc.)
    /// @param index The index of the chain ID
    /// @return The chain ID for the token
    function getTokenChainIdForTypeAt(address token, string memory chainType, uint256 index)
        public
        view
        returns (uint256)
    {
        return _tokenChainIds[token][chainType].at(index);
    }

    /// @notice Get the tokens chain IDs, paginated
    /// @param token The address of the token
    /// @param chainType The type of the chain (e.g. "EVM", "COSMW", "SOL", etc.)
    /// @param index The index of the chain ID
    /// @param count The number of chain IDs to return
    /// @return The chain IDs for the token
    function getTokenChainIdsForTypeFrom(address token, string memory chainType, uint256 index, uint256 count)
        public
        view
        returns (uint256[] memory)
    {
        EnumerableSet.UintSet storage chainIds = _tokenChainIds[token][chainType];
        uint256 totalLength = chainIds.length();
        if (index >= totalLength) {
            return new uint256[](0);
        }
        if (index + count > totalLength) {
            count = totalLength - index;
        }
        uint256[] memory items = new uint256[](count);
        for (uint256 i; i < count; i++) {
            items[i] = chainIds.at(index + i);
        }
        return items;
    }
}
