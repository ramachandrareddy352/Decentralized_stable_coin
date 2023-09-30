# Foundry DeFi Stablecoin

# About

This project is meant to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to the USD.

### Overview

A decentralized stablecoin is a type of cryptocurrency designed to maintain a stable value relative to a reference asset, such as a national currency like the US Dollar or a commodity like gold. Unlike traditional cryptocurrencies like Bitcoin, which are known for their price volatility, stablecoins are engineered to minimize fluctuations in value.

### Key Features

- **Stability**: The primary goal of a decentralized stablecoin is to offer price stability, making it a reliable medium of exchange and a store of value.
- **Collateralization**: Many decentralized stablecoins are backed by collateral, which can include cryptocurrencies, fiat currencies, or other assets. This collateral provides a reserve to support the stablecoin's value.
- **Decentralization**: Decentralized stablecoins often run on blockchain networks and utilize decentralized finance (DeFi) protocols to maintain trust and transparency. They are not controlled by a single entity.
- **Smart Contracts**: Smart contracts are frequently used to automate the issuance, redemption, and governance of decentralized stablecoins. These contracts ensure that the stablecoin operates according to predefined rules.
- **Transparency**: The operations of decentralized stablecoins, including collateral holdings, issuance, and redemption, are typically transparent and verifiable on the blockchain.

### Use Cases

- **Digital Payments**: Decentralized stablecoins can be used for digital payments, offering a stable alternative to volatile cryptocurrencies.
- **Remittances**: They are well-suited for cross-border remittances due to their stability and low transaction costs.
- **Trading**: Traders often use stablecoins as a safe haven during periods of high volatility in other cryptocurrencies.
- **Lending and Borrowing**: Stablecoins play a crucial role in DeFi platforms, where users can earn interest by lending stablecoins or access liquidity by borrowing them.

### Examples

- **DAI**: DAI is a decentralized stablecoin on the Ethereum blockchain, maintained by the MakerDAO decentralized autonomous organization.
- **USDC**: USDC is a centralized stablecoin issued by regulated financial institutions and is widely used in the cryptocurrency ecosystem.
- **Tether (USDT)**: USDT is one of the earliest stablecoins and is known for its high liquidity, though its collateral has been a topic of debate.

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`

## Quickstart

```
git clone https://github.com/ramachandrareddy352/Decentralized_stable_coin
cd Decentralized_stable_coin
forge build
```

## Installation packages
- There are some packages to install for our project
- after cloning into repository install these packages and run build command
  
```
forge install chainlink-brownie-contracts
forge install openzeppelin/openzeppelin-contracts
forge install foundry-devops
```

# Updates
- The latest version of openzeppelin-contracts has changes in the ERC20Mock file. To follow along with the course, you need to install version 4.8.3 which can be done by ```forge install openzeppelin/openzeppelin-contracts@v4.8.3 --no-commit``` instead of ```forge install openzeppelin/openzeppelin-contracts --no-commit```

# Usage

## Start a local node

```
make anvil
```

## Deploy

This will default to your local node. You need to have it running in another terminal in order for it to deploy.
```
make deploy
```

## Testing

for testing the entire test files run command -> forge test
for testing a particular test file run the command -> forge test --match-path <test_file_name>
for testing a particular test use -> forge test --match-test <test_name>
To run all tests in a forked environment, such as a forked Ethereum mainnet, pass an RPC URL via the --fork-url flag -> forge test --fork-url <your_rpc_url>


### Test Coverage

```
forge coverage
```
and for coverage based testing: 

```
forge coverage --report debug
```


# Deployment to a testnet or mainnet

1. Setup environment variables
You'll want to set your `SEPOLIA_RPC_URL` and `PRIVATE_KEY` as environment variables. You can add them to a `.env` file, similar to what you see in `.env.example`.

- `PRIVATE_KEY`: The private key of your account (like from [metamask](https://metamask.io/)). 
- `SEPOLIA_RPC_URL`: This is url of the sepolia testnet node you're working with. You can get setup with one for free from [Alchemy](https://alchemy.com/?a=673c802981)

Optionally, add your `ETHERSCAN_API_KEY` if you want to verify your contract on [Etherscan](https://etherscan.io/).

1. Get testnet ETH
Head over to ([https://faucets.chain.link/](https://sepoliafaucet.com/)) and get some testnet ETH. You should see the ETH show up in your metamask.

2. Deploy
```
make deploy ARGS="--network sepolia"
```

## Scripts

Instead of scripts, we can directly use the `cast` command to interact with the contract. 
For example, on Sepolia:

1. Get some WETH 
```
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "deposit()" --value 0.1ether --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

2. Approve the WETH
```
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "approve(address,uint256)" 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 1000000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

3. Deposit and Mint DSC
```
cast send 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 "depositCollateralAndMintDsc(address,uint256,uint256)" 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 100000000000000000 10000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```


## Estimate gas

You can estimate how much gas things cost by running:
```
forge snapshot
```
And you'll see an output file called `.gas-snapshot`


# Formatting

To run code formatting:
```
forge fmt
```

# Thank you!
