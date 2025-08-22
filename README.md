## CL8Y.com/Bridge EVM Smart Contracts

**A community operated bridge, open to all and secured by CL8Y, for EVM, CosmWasm, Sol, and more.**
This repo contains the EVM smart contracts for the CL8Y Bridge, licensed under AGPL.

## Deployments

### BSC Testnet, opBNB Testnet

AccessManagerEnumerable: 0xC86844f2c260a4c2047e9b55c615ac844412079B
ChainRegistry: 0x6A6120402C89e1a88707684e26E50A6CBCe81e92
TokenRegistry: 0x1f2a8647830c2AA9827C6a43533C4c35088Fc926
MintBurn: 0x60D1d3BDD3999D318c953ABfFbF7793182775c1e
LockUnlock: 0x843cd5E5449dd98A00F3C7cbd02CEDF618d6017b
Cl8YBridge: 0x02E44B3e9d1cE8e7F33bfC26135216Bd6b6aF1Cf
DatastoreSetAddress: 0x77145569735Cf9B6cF43930Dd8c1875196e7e5ac
GuardBridge: 0x7DEe783CbF61Dc6f2714B7766C943Ae608572A5C
BlacklistBasic: 0xF6163564C39cde32db28B3153B868c20674A072f
TokenRateLimit: 0x52bFD64960dF9015C203b4C1530Db789783D403e
BridgeRouter: 0x757D6483a7CB8E77E154253fdA2C76D10b78C591
FactoryTokenCl8yBridged: 0x06D43D56db1d9A50796B0386B724b8EE467b4ca1

## Deployments Old (v0.0.1)

### BSC (56)

AccessManager: `0xeAaFB20F2b5612254F0da63cf4E0c9cac710f8aF`
FactoryTokenCl8yBridged: `0x4C6e7a15b0CA53408BcB84759877f16e272eeeeA`

## instructions

Build: `forge build`
Test: `forge test`
Coverage: `forge coverage --no-match-coverage "(test|script)/**"`
For lcov, add `--report lcov`

## deployment

Key variables are set in the script, and should be updated correctly for the network.

Single-command deploy (DeployPart1):
`forge script script/DeployPart1.s.sol:DeployPart1 --broadcast --verify -vvv --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY -i 1 --sender $DEPLOYER_ADDRESS`

Notes:

- Requires env vars: `DEPLOY_SALT`, `WETH_ADDRESS`, `RPC_URL`, `ETHERSCAN_API_KEY`, `DEPLOYER_ADDRESS`.
- Uses CREATE2 salts derived from `DEPLOY_SALT` for deterministic addresses.
