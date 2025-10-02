# Money Plant Aptos

A Move smart contract for a money pot system on Aptos blockchain.

## Overview

This project implements a "money pot" system where:

- Users can create pots with APT tokens
- Other users can attempt to solve challenges to win the pot
- Successful hunters get 40% of the pot, platform gets 60%
- Pots expire after a set duration and return funds to creators

## Features

- Create money pots with configurable amounts and durations
- Attempt to solve pots with entry fees
- Oracle-based completion verification
- Automatic payout distribution
- Event logging for all actions
- Comprehensive test suite

## Quick Start

### Prerequisites

- Aptos CLI installed
- Just command runner (optional, for using justfile commands)

### Building and Testing

```bash
# Build the contract
aptos move compile --dev

# Run tests
aptos move test --dev

# Or use just commands
just build
just test
```

### Deployment

#### Option 1: Using Just Commands (Recommended)

```bash
# Full deployment workflow
just deploy-full

# Or step by step
just init-account
just fund
just deploy
```

#### Option 2: Manual Deployment

```bash
# Initialize account
aptos init --network devnet

# Fund account (devnet only)
aptos account fund-with-faucet --profile default --url https://fullnode.devnet.aptoslabs.com --faucet-url https://faucet.devnet.aptoslabs.com

# Deploy contract
aptos move deploy-object --address-name money_pot --assume-yes
```

### Using the Contract

After deployment, update the `get-object-address` variable in the justfile with your deployed contract address.

```bash
# Create a pot (amount, duration_seconds, fee, one_fa_address)
just create-pot 1000000 3600 100000 0x123...

# Attempt a pot
just attempt-pot 0

# View pots
just get-pots
just get-active-pots
just get-pot 0
```

## Available Commands

Run `just help` to see all available commands:

- `build` - Compile the Move contract
- `test` - Run unit tests
- `deploy` - Deploy the contract
- `upgrade <addr>` - Upgrade existing contract
- `create-pot <args>` - Create a new money pot
- `attempt-pot <id>` - Attempt to solve a pot
- `get-pots` - List all pots
- `get-active-pots` - List active pots
- `get-pot <id>` - Get pot details
- `get-attempt <id>` - Get attempt details

## Contract Functions

### Public Entry Functions

- `create_pot_entry(creator, amount, duration_seconds, fee, one_fa_address)` - Create a new pot
- `attempt_pot_entry(hunter, pot_id)` - Attempt to solve a pot
- `attempt_completed(oracle, attempt_id, status)` - Mark attempt as completed (oracle only)
- `claim_winnings(hunter, attempt_id)` - Claim winnings for successful attempt
- `expire_pot(caller, pot_id)` - Expire a pot and return funds to creator

### View Functions

- `get_pots()` - Get all pot IDs
- `get_active_pots()` - Get active pot IDs
- `get_pot(pot_id)` - Get pot details
- `get_attempt(attempt_id)` - Get attempt details

## Configuration

### Addresses

The contract uses these named addresses:

- `money_pot` - Main contract address
- `trusted_oracle` - Oracle address for attempt verification
- `platform` - Platform address for fee collection

### Constants

- `DIFFICULTY_MOD: 11` - Difficulty calculation modifier
- `HUNTER_SHARE_PERCENT: 40` - Percentage of pot that goes to successful hunter

## Testing

The project includes comprehensive unit tests covering:

- Pot creation
- Attempt submission
- Data retrieval
- Edge cases

Run tests with:

```bash
aptos move test --dev
```

## Network Support

- **Devnet**: Full support with faucet funding
- **Testnet**: Manual funding required
- **Mainnet**: Real APT required

## Security Notes

- Oracle address must be set to a trusted address
- Platform address should be controlled by the project team
- All coin transfers are handled through the Aptos framework
- Entry fees are automatically added to pot totals

## License

MIT License
