// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {FactoryTokenCl8yBridged} from "../src/FactoryTokenCl8yBridged.sol";
import {TokenCl8yBridged} from "../src/TokenCl8yBridged.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

contract FactoryTokenCl8yBridgedTest is Test {
    FactoryTokenCl8yBridged public factory;
    AccessManager public accessManager;

    address public owner = address(1);
    address public creator = address(2);
    address public unauthorizedUser = address(3);

    string constant BASE_NAME = "Test Token";
    string constant BASE_SYMBOL = "TEST";
    uint256 constant ORIGIN_CHAIN_ID = 1;
    string constant ORIGIN_CHAIN_TYPE = "EVM";
    string constant LOGO_LINK = "https://example.com/logo.png";

    string constant NAME_SUFFIX = " cl8y.com/bridge";
    string constant SYMBOL_SUFFIX = "-cb";

    function setUp() public {
        // Deploy access manager with owner
        vm.prank(owner);
        accessManager = new AccessManager(owner);

        // Deploy factory with access manager as authority
        factory = new FactoryTokenCl8yBridged(address(accessManager));

        // Create a creator role and grant it to the creator address
        vm.startPrank(owner);
        uint64 creatorRole = 1;
        accessManager.grantRole(creatorRole, creator, 0);

        // Create array for function selectors
        bytes4[] memory createTokenSelectors = new bytes4[](1);
        createTokenSelectors[0] = factory.createToken.selector;

        // Set function role for createToken function
        accessManager.setTargetFunctionRole(address(factory), createTokenSelectors, creatorRole);
        vm.stopPrank();
    }

    // Constructor Tests
    function test_Constructor() public view {
        assertEq(factory.authority(), address(accessManager));
        assertEq(factory.getTokensCount(), 0);
        assertEq(factory.logoLink(), "");
    }

    function test_Constructor_WithDifferentAuthority() public {
        address newAuthority = address(999);
        FactoryTokenCl8yBridged newFactory = new FactoryTokenCl8yBridged(newAuthority);

        assertEq(newFactory.authority(), newAuthority);
        assertEq(newFactory.getTokensCount(), 0);
    }

    // Token Creation Tests
    function test_CreateToken_Success() public {
        vm.prank(creator);
        address tokenAddress =
            factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        // Check token was created
        assertTrue(tokenAddress != address(0));
        assertEq(factory.getTokensCount(), 1);
        assertTrue(factory.isTokenCreated(tokenAddress));
        assertEq(factory.logoLink(), LOGO_LINK);

        // Check token properties
        TokenCl8yBridged token = TokenCl8yBridged(tokenAddress);
        assertEq(token.name(), string.concat(BASE_NAME, NAME_SUFFIX));
        assertEq(token.symbol(), string.concat(BASE_SYMBOL, SYMBOL_SUFFIX));
        assertEq(token.ORIGIN_CHAIN_ID(), ORIGIN_CHAIN_ID);
        assertEq(token.ORIGIN_CHAIN_TYPE(), ORIGIN_CHAIN_TYPE);
        assertEq(token.logoLink(), LOGO_LINK);
        assertEq(token.authority(), address(accessManager));
    }

    function test_CreateToken_MultipleTokens() public {
        string memory name2 = "Another Token";
        string memory symbol2 = "ANOTHER";
        uint256 originChainId2 = 137;
        string memory originChainType2 = "COSMW";
        string memory logoLink2 = "https://example.com/logo2.png";

        vm.startPrank(creator);

        // Create first token
        address token1 = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        // Create second token
        address token2 = factory.createToken(name2, symbol2, originChainId2, originChainType2, logoLink2);

        vm.stopPrank();

        // Check both tokens exist
        assertEq(factory.getTokensCount(), 2);
        assertTrue(factory.isTokenCreated(token1));
        assertTrue(factory.isTokenCreated(token2));
        assertTrue(token1 != token2);
        assertEq(factory.logoLink(), logoLink2); // Should be the last one set

        // Check token properties
        TokenCl8yBridged tokenContract1 = TokenCl8yBridged(token1);
        TokenCl8yBridged tokenContract2 = TokenCl8yBridged(token2);

        assertEq(tokenContract1.name(), string.concat(BASE_NAME, NAME_SUFFIX));
        assertEq(tokenContract2.name(), string.concat(name2, NAME_SUFFIX));
        assertEq(tokenContract1.symbol(), string.concat(BASE_SYMBOL, SYMBOL_SUFFIX));
        assertEq(tokenContract2.symbol(), string.concat(symbol2, SYMBOL_SUFFIX));
    }

    function test_CreateToken_RevertWhen_Unauthorized() public {
        vm.expectRevert();
        vm.prank(unauthorizedUser);
        factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);
    }

    // Token Retrieval Tests
    function test_GetAllTokens_Empty() public view {
        address[] memory tokens = factory.getAllTokens();
        assertEq(tokens.length, 0);
    }

    function test_GetAllTokens_WithTokens() public {
        vm.startPrank(creator);

        address token1 = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);
        address token2 = factory.createToken("Token 2", "T2", 137, "COSMW", LOGO_LINK);
        address token3 = factory.createToken("Token 3", "T3", 56, "SOL", LOGO_LINK);

        vm.stopPrank();

        address[] memory tokens = factory.getAllTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], token1);
        assertEq(tokens[1], token2);
        assertEq(tokens[2], token3);
    }

    function test_GetTokensCount() public {
        assertEq(factory.getTokensCount(), 0);

        vm.startPrank(creator);
        factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);
        assertEq(factory.getTokensCount(), 1);

        factory.createToken("Token 2", "T2", 137, "COSMW", LOGO_LINK);
        assertEq(factory.getTokensCount(), 2);
        vm.stopPrank();
    }

    function test_GetTokenAt() public {
        vm.startPrank(creator);

        address token1 = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);
        address token2 = factory.createToken("Token 2", "T2", 137, "COSMW", LOGO_LINK);

        vm.stopPrank();

        assertEq(factory.getTokenAt(0), token1);
        assertEq(factory.getTokenAt(1), token2);
    }

    function test_GetTokenAt_RevertWhen_IndexOutOfBounds() public {
        vm.expectRevert();
        factory.getTokenAt(0);

        vm.prank(creator);
        factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        vm.expectRevert();
        factory.getTokenAt(1);
    }

    function test_GetTokensFrom_Empty() public view {
        address[] memory tokens = factory.getTokensFrom(0, 10);
        assertEq(tokens.length, 0);
    }

    function test_GetTokensFrom_IndexOutOfBounds() public {
        vm.prank(creator);
        factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        address[] memory tokens = factory.getTokensFrom(5, 10);
        assertEq(tokens.length, 0);
    }

    function test_GetTokensFrom_PartialRange() public {
        vm.startPrank(creator);

        factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);
        address token2 = factory.createToken("Token 2", "T2", 137, "COSMW", LOGO_LINK);
        address token3 = factory.createToken("Token 3", "T3", 56, "SOL", LOGO_LINK);
        factory.createToken("Token 4", "T4", 43114, "EVM", LOGO_LINK);

        vm.stopPrank();

        // Get tokens from index 1, count 2
        address[] memory tokens = factory.getTokensFrom(1, 2);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token2);
        assertEq(tokens[1], token3);
    }

    function test_GetTokensFrom_ExceedsAvailable() public {
        vm.startPrank(creator);

        factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);
        address token2 = factory.createToken("Token 2", "T2", 137, "COSMW", LOGO_LINK);

        vm.stopPrank();

        // Request more tokens than available
        address[] memory tokens = factory.getTokensFrom(1, 5);
        assertEq(tokens.length, 1); // Should only return 1 token (from index 1)
        assertEq(tokens[0], token2);
    }

    function test_GetTokensFrom_FullRange() public {
        vm.startPrank(creator);

        address token1 = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);
        address token2 = factory.createToken("Token 2", "T2", 137, "COSMW", LOGO_LINK);
        address token3 = factory.createToken("Token 3", "T3", 56, "SOL", LOGO_LINK);

        vm.stopPrank();

        address[] memory tokens = factory.getTokensFrom(0, 10);
        assertEq(tokens.length, 3);
        assertEq(tokens[0], token1);
        assertEq(tokens[1], token2);
        assertEq(tokens[2], token3);
    }

    // Token Validation Tests
    function test_IsTokenCreated_True() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        assertTrue(factory.isTokenCreated(token));
    }

    function test_IsTokenCreated_False() public {
        address randomAddress = address(999);
        assertFalse(factory.isTokenCreated(randomAddress));

        // Create a token, but check a different address
        vm.prank(creator);
        factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        assertFalse(factory.isTokenCreated(randomAddress));
    }

    // Access Control Tests
    function test_AccessControl_OnlyAuthorizedCanCreate() public {
        // Authorized user can create
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);
        assertTrue(factory.isTokenCreated(token));

        // Unauthorized user cannot create
        vm.expectRevert();
        vm.prank(unauthorizedUser);
        factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);
    }

    // Edge Cases
    function test_CreateToken_EmptyStrings() public {
        vm.prank(creator);
        address token = factory.createToken("", "", ORIGIN_CHAIN_ID, "", "");

        TokenCl8yBridged tokenContract = TokenCl8yBridged(token);
        assertEq(tokenContract.name(), NAME_SUFFIX);
        assertEq(tokenContract.symbol(), SYMBOL_SUFFIX);
        assertEq(tokenContract.ORIGIN_CHAIN_TYPE(), "");
        assertEq(tokenContract.logoLink(), "");
    }

    function test_CreateToken_LongStrings() public {
        string memory longName = "This is a very long token name that exceeds normal expectations for token names";
        string memory longSymbol = "VERYLONGSYMBOL";
        string memory longChainType = "VeryLongChainTypeName";
        string memory longLogoLink =
            "https://example.com/very/long/path/to/logo/image/that/exceeds/normal/expectations.png";

        vm.prank(creator);
        address token = factory.createToken(longName, longSymbol, ORIGIN_CHAIN_ID, longChainType, longLogoLink);

        TokenCl8yBridged tokenContract = TokenCl8yBridged(token);
        assertEq(tokenContract.name(), string.concat(longName, NAME_SUFFIX));
        assertEq(tokenContract.symbol(), string.concat(longSymbol, SYMBOL_SUFFIX));
        assertEq(tokenContract.ORIGIN_CHAIN_TYPE(), longChainType);
        assertEq(tokenContract.logoLink(), longLogoLink);
    }

    function test_CreateToken_DifferentChainTypes() public {
        string[] memory chainTypes = new string[](4);
        chainTypes[0] = "EVM";
        chainTypes[1] = "COSMW";
        chainTypes[2] = "SOL";
        chainTypes[3] = "SUI";

        vm.startPrank(creator);

        for (uint256 i = 0; i < chainTypes.length; i++) {
            address token = factory.createToken(
                string.concat("Token ", vm.toString(i)),
                string.concat("T", vm.toString(i)),
                i + 1,
                chainTypes[i],
                LOGO_LINK
            );

            TokenCl8yBridged tokenContract = TokenCl8yBridged(token);
            assertEq(tokenContract.ORIGIN_CHAIN_TYPE(), chainTypes[i]);
        }

        vm.stopPrank();

        assertEq(factory.getTokensCount(), 4);
    }

    // Fuzz Tests
    function testFuzz_CreateToken(
        string memory name,
        string memory symbol,
        uint256 chainId,
        string memory chainType,
        string memory logoLink
    ) public {
        // Assume reasonable constraints
        vm.assume(bytes(name).length <= 100);
        vm.assume(bytes(symbol).length <= 20);
        vm.assume(chainId < type(uint64).max);
        vm.assume(bytes(chainType).length <= 50);
        vm.assume(bytes(logoLink).length <= 200);

        vm.prank(creator);
        address token = factory.createToken(name, symbol, chainId, chainType, logoLink);

        assertTrue(factory.isTokenCreated(token));
        assertEq(factory.getTokensCount(), 1);

        TokenCl8yBridged tokenContract = TokenCl8yBridged(token);
        assertEq(tokenContract.name(), string.concat(name, NAME_SUFFIX));
        assertEq(tokenContract.symbol(), string.concat(symbol, SYMBOL_SUFFIX));
        assertEq(tokenContract.ORIGIN_CHAIN_ID(), chainId);
        assertEq(tokenContract.ORIGIN_CHAIN_TYPE(), chainType);
        assertEq(tokenContract.logoLink(), logoLink);
    }

    function testFuzz_GetTokensFrom(uint256 index, uint256 count) public {
        // Create some tokens first
        vm.startPrank(creator);
        for (uint256 i = 0; i < 5; i++) {
            factory.createToken(
                string.concat("Token ", vm.toString(i)), string.concat("T", vm.toString(i)), i + 1, "EVM", LOGO_LINK
            );
        }
        vm.stopPrank();

        // Bound the inputs to reasonable values
        index = bound(index, 0, 10);
        count = bound(count, 0, 10);

        address[] memory tokens = factory.getTokensFrom(index, count);

        // Results should never exceed total tokens
        assertTrue(tokens.length <= 5);

        // If index is out of bounds, should return empty array
        if (index >= 5) {
            assertEq(tokens.length, 0);
        } else {
            // Should return min(count, remaining tokens)
            uint256 expectedLength = count;
            if (index + count > 5) {
                expectedLength = 5 - index;
            }
            assertEq(tokens.length, expectedLength);
        }
    }

    // Token Chain IDs Tests
    function test_TokenChainIds_SingleToken() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        // Check that the chain ID was recorded
        uint256[] memory chainIds = factory.getAllTokenChainIdsForType(token, ORIGIN_CHAIN_TYPE);
        assertEq(chainIds.length, 1);
        assertEq(chainIds[0], ORIGIN_CHAIN_ID);

        // Check count
        assertEq(factory.getTokenChainIdsForTypeCount(token, ORIGIN_CHAIN_TYPE), 1);

        // Check at index
        assertEq(factory.getTokenChainIdForTypeAt(token, ORIGIN_CHAIN_TYPE, 0), ORIGIN_CHAIN_ID);
    }

    function test_TokenChainIds_MultipleChainTypes() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        // Initially only EVM chain should exist
        uint256[] memory evmChainIds = factory.getAllTokenChainIdsForType(token, "EVM");
        assertEq(evmChainIds.length, 1);
        assertEq(evmChainIds[0], ORIGIN_CHAIN_ID);

        // Other chain types should be empty
        uint256[] memory cosmwChainIds = factory.getAllTokenChainIdsForType(token, "COSMW");
        assertEq(cosmwChainIds.length, 0);

        uint256[] memory solChainIds = factory.getAllTokenChainIdsForType(token, "SOL");
        assertEq(solChainIds.length, 0);
    }

    function test_TokenChainIds_MultipleTokensSameChainType() public {
        vm.startPrank(creator);

        // Create tokens with different chain IDs but same chain type
        address token1 = factory.createToken(BASE_NAME, BASE_SYMBOL, 1, "EVM", LOGO_LINK);
        address token2 = factory.createToken("Token 2", "T2", 137, "EVM", LOGO_LINK);
        address token3 = factory.createToken("Token 3", "T3", 56, "EVM", LOGO_LINK);

        vm.stopPrank();

        // Each token should have its own chain ID
        uint256[] memory token1ChainIds = factory.getAllTokenChainIdsForType(token1, "EVM");
        assertEq(token1ChainIds.length, 1);
        assertEq(token1ChainIds[0], 1);

        uint256[] memory token2ChainIds = factory.getAllTokenChainIdsForType(token2, "EVM");
        assertEq(token2ChainIds.length, 1);
        assertEq(token2ChainIds[0], 137);

        uint256[] memory token3ChainIds = factory.getAllTokenChainIdsForType(token3, "EVM");
        assertEq(token3ChainIds.length, 1);
        assertEq(token3ChainIds[0], 56);
    }

    function test_TokenChainIds_DifferentChainTypes() public {
        vm.startPrank(creator);

        // Create tokens with different chain types
        address token1 = factory.createToken(BASE_NAME, BASE_SYMBOL, 1, "EVM", LOGO_LINK);
        address token2 = factory.createToken("Token 2", "T2", 137, "COSMW", LOGO_LINK);
        address token3 = factory.createToken("Token 3", "T3", 56, "SOL", LOGO_LINK);

        vm.stopPrank();

        // Check EVM chain IDs
        uint256[] memory evmChainIds = factory.getAllTokenChainIdsForType(token1, "EVM");
        assertEq(evmChainIds.length, 1);
        assertEq(evmChainIds[0], 1);

        // Check COSMW chain IDs
        uint256[] memory cosmwChainIds = factory.getAllTokenChainIdsForType(token2, "COSMW");
        assertEq(cosmwChainIds.length, 1);
        assertEq(cosmwChainIds[0], 137);

        // Check SOL chain IDs
        uint256[] memory solChainIds = factory.getAllTokenChainIdsForType(token3, "SOL");
        assertEq(solChainIds.length, 1);
        assertEq(solChainIds[0], 56);

        // Cross-check: token1 should have no COSMW or SOL entries
        assertEq(factory.getAllTokenChainIdsForType(token1, "COSMW").length, 0);
        assertEq(factory.getAllTokenChainIdsForType(token1, "SOL").length, 0);
    }

    function test_TokenChainIds_EmptyForNonexistentToken() public view {
        address nonexistentToken = address(999);

        uint256[] memory chainIds = factory.getAllTokenChainIdsForType(nonexistentToken, "EVM");
        assertEq(chainIds.length, 0);

        assertEq(factory.getTokenChainIdsForTypeCount(nonexistentToken, "EVM"), 0);
    }

    function test_TokenChainIds_EmptyForNonexistentChainType() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, "EVM", LOGO_LINK);

        // Query for a chain type that doesn't exist
        uint256[] memory chainIds = factory.getAllTokenChainIdsForType(token, "NONEXISTENT");
        assertEq(chainIds.length, 0);

        assertEq(factory.getTokenChainIdsForTypeCount(token, "NONEXISTENT"), 0);
    }

    function test_TokenChainIds_GetAtIndex() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        // Test getting chain ID at valid index
        uint256 chainId = factory.getTokenChainIdForTypeAt(token, ORIGIN_CHAIN_TYPE, 0);
        assertEq(chainId, ORIGIN_CHAIN_ID);
    }

    function test_TokenChainIds_GetAtIndex_RevertOnInvalidIndex() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, ORIGIN_CHAIN_TYPE, LOGO_LINK);

        // Test getting chain ID at invalid index
        vm.expectRevert();
        factory.getTokenChainIdForTypeAt(token, ORIGIN_CHAIN_TYPE, 1);
    }

    function test_TokenChainIds_GetAtIndex_RevertOnEmptySet() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, "EVM", LOGO_LINK);

        // Test getting chain ID from non-existent chain type
        vm.expectRevert();
        factory.getTokenChainIdForTypeAt(token, "COSMW", 0);
    }

    function test_TokenChainIds_PaginatedRetrieval_Empty() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, "EVM", LOGO_LINK);

        // Test pagination for empty chain type
        uint256[] memory chainIds = factory.getTokenChainIdsForTypeFrom(token, "COSMW", 0, 10);
        assertEq(chainIds.length, 0);
    }

    function test_TokenChainIds_PaginatedRetrieval_IndexOutOfBounds() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, "EVM", LOGO_LINK);

        // Test pagination with out of bounds index
        uint256[] memory chainIds = factory.getTokenChainIdsForTypeFrom(token, "EVM", 5, 10);
        assertEq(chainIds.length, 0);
    }

    function test_TokenChainIds_PaginatedRetrieval_PartialRange() public {
        // This test would be more meaningful if the contract allowed adding multiple chain IDs
        // for the same token and chain type. Currently, each token creation only adds one chain ID.
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, "EVM", LOGO_LINK);

        // Test pagination with valid range
        uint256[] memory chainIds = factory.getTokenChainIdsForTypeFrom(token, "EVM", 0, 1);
        assertEq(chainIds.length, 1);
        assertEq(chainIds[0], ORIGIN_CHAIN_ID);
    }

    function test_TokenChainIds_PaginatedRetrieval_ExceedsAvailable() public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, "EVM", LOGO_LINK);

        // Test pagination requesting more than available
        uint256[] memory chainIds = factory.getTokenChainIdsForTypeFrom(token, "EVM", 0, 5);
        assertEq(chainIds.length, 1); // Should only return 1 chain ID
        assertEq(chainIds[0], ORIGIN_CHAIN_ID);
    }

    function test_TokenChainIds_ComplexScenario() public {
        vm.startPrank(creator);

        // Create multiple tokens with various chain configurations
        address token1 = factory.createToken("Bitcoin", "BTC", 1, "EVM", LOGO_LINK);
        address token2 = factory.createToken("Ethereum", "ETH", 1, "EVM", LOGO_LINK);
        address token3 = factory.createToken("Cosmos", "ATOM", 118, "COSMW", LOGO_LINK);
        address token4 = factory.createToken("Solana", "SOL", 101, "SOL", LOGO_LINK);

        vm.stopPrank();

        // Verify EVM tokens
        uint256[] memory token1EvmChains = factory.getAllTokenChainIdsForType(token1, "EVM");
        assertEq(token1EvmChains.length, 1);
        assertEq(token1EvmChains[0], 1);

        uint256[] memory token2EvmChains = factory.getAllTokenChainIdsForType(token2, "EVM");
        assertEq(token2EvmChains.length, 1);
        assertEq(token2EvmChains[0], 1);

        // Verify COSMW token
        uint256[] memory token3CosmwChains = factory.getAllTokenChainIdsForType(token3, "COSMW");
        assertEq(token3CosmwChains.length, 1);
        assertEq(token3CosmwChains[0], 118);

        // Verify SOL token
        uint256[] memory token4SolChains = factory.getAllTokenChainIdsForType(token4, "SOL");
        assertEq(token4SolChains.length, 1);
        assertEq(token4SolChains[0], 101);

        // Cross-verify: tokens should not have chain IDs for other chain types
        assertEq(factory.getAllTokenChainIdsForType(token1, "COSMW").length, 0);
        assertEq(factory.getAllTokenChainIdsForType(token1, "SOL").length, 0);
        assertEq(factory.getAllTokenChainIdsForType(token3, "EVM").length, 0);
        assertEq(factory.getAllTokenChainIdsForType(token4, "EVM").length, 0);
    }

    // Fuzz Tests for Token Chain IDs
    function testFuzz_TokenChainIds_BasicFunctionality(
        string memory name,
        string memory symbol,
        uint256 chainId,
        string memory chainType
    ) public {
        // Assume reasonable constraints
        vm.assume(bytes(name).length <= 50);
        vm.assume(bytes(symbol).length <= 10);
        vm.assume(chainId < type(uint64).max);
        vm.assume(bytes(chainType).length <= 20);
        vm.assume(bytes(chainType).length > 0); // Chain type cannot be empty

        vm.prank(creator);
        address token = factory.createToken(name, symbol, chainId, chainType, LOGO_LINK);

        // Verify chain ID was recorded
        uint256[] memory chainIds = factory.getAllTokenChainIdsForType(token, chainType);
        assertEq(chainIds.length, 1);
        assertEq(chainIds[0], chainId);

        // Verify count
        assertEq(factory.getTokenChainIdsForTypeCount(token, chainType), 1);

        // Verify at index
        assertEq(factory.getTokenChainIdForTypeAt(token, chainType, 0), chainId);
    }

    function testFuzz_TokenChainIds_PaginatedRetrieval(uint256 index, uint256 count) public {
        vm.prank(creator);
        address token = factory.createToken(BASE_NAME, BASE_SYMBOL, ORIGIN_CHAIN_ID, "EVM", LOGO_LINK);

        // Bound inputs to reasonable values
        index = bound(index, 0, 10);
        count = bound(count, 0, 10);

        uint256[] memory chainIds = factory.getTokenChainIdsForTypeFrom(token, "EVM", index, count);

        // Results should never exceed available chain IDs (which is 1 in this case)
        assertTrue(chainIds.length <= 1);

        // If index is out of bounds, should return empty array
        if (index >= 1) {
            assertEq(chainIds.length, 0);
        } else {
            // Should return min(count, remaining chain IDs)
            uint256 expectedLength = count > 0 ? 1 : 0;
            assertEq(chainIds.length, expectedLength);
            if (chainIds.length > 0) {
                assertEq(chainIds[0], ORIGIN_CHAIN_ID);
            }
        }
    }
}
