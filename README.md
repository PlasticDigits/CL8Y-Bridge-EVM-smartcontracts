## CL8Y.com/Bridge EVM Smart Contracts

**A community operated bridge, open to all and secured by CL8Y, for EVM, CosmWasm, Sol, and more.**
This repo contains the EVM smart contracts for the CL8Y Bridge, licensed under GPL-3.0.

## Deployments

### BSC (56)

AccessManager: `0xeAaFB20F2b5612254F0da63cf4E0c9cac710f8aF`
FactoryTokenCl8yBridged: `0x4C6e7a15b0CA53408BcB84759877f16e272eeeeA`

## instructions

Build: `forge build`
Test: `forge test`
Coverage: `forge coverage --no-match-coverage "test/**`--re

## deployment

Key variables are set in the script, and should be updated correctly for the network.
forge script script/FactoryTokenCl8yBridged.s.sol:FactoryTokenCl8yBridgedScript --broadcast --verify -vvv --rpc-url $RPC_URL --etherscan-api-key $ETHERSCAN_API_KEY -i 1 --sender $DEPLOYER_ADDRESS
