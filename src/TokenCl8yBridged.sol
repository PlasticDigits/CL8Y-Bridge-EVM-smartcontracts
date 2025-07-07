// SPDX-License-Identifier: GPL-3.0
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.30;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title TokenCl8yBridged
/// @notice A token that can be bridged from another chain, or is native to the current chain
/// @dev This token can be bridged from another chain and can be used on the current chain
contract TokenCl8yBridged is ERC20, ERC20Burnable, AccessManaged, ERC20Permit {
    /// @notice The chain ID where this token was originally minted
    uint256 public immutable ORIGIN_CHAIN_ID;
    /// @notice The type of the origin chain (e.g. "EVM", "CosmWasm", "Sol", etc.)
    string public ORIGIN_CHAIN_TYPE;
    /// @notice The link to the token's logo (can be ipfs:// or https://)
    string public logoLink;
    /// @notice The chain ID where this token was deployed
    uint256 private immutable DEPLOYED_CHAIN_ID = block.chainid;

    /// @notice Constructor
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param initialAuthority The address that will be the initial authority
    /// @param _originChainId The chain ID where this token was originally minted
    /// @param _originChainType The type of the origin chain (e.g. "EVM", "CosmWasm", "Sol", etc.)
    /// @param _logoLink The link to the token's logo (can be ipfs:// or https://)
    constructor(
        string memory name,
        string memory symbol,
        address initialAuthority,
        uint256 _originChainId,
        string memory _originChainType,
        string memory _logoLink
    ) ERC20(name, symbol) AccessManaged(initialAuthority) ERC20Permit(name) {
        ORIGIN_CHAIN_ID = _originChainId;
        ORIGIN_CHAIN_TYPE = _originChainType;
        logoLink = _logoLink;
    }

    /// @notice Mint tokens to an address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint (18 decimals)
    function mint(address to, uint256 amount) public restricted {
        _mint(to, amount);
    }

    /// @notice Set the logo link for the token
    /// @param _logoLink The link to the token's logo (can be ipfs:// or https://)
    function setLogoLink(string memory _logoLink) public restricted {
        logoLink = _logoLink;
    }

    /// @notice Returns whether this token is native to the current chain
    /// @return True if the token is native to the current chain, false otherwise
    function isNative() public view returns (bool) {
        return ORIGIN_CHAIN_ID == block.chainid;
    }
}
