set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-NoLogo", "-Command"]
#set allow-duplicate-recipe
#set positional-arguments
set dotenv-filename := ".env"
set export

# Default network (change to testnet/mainnet as needed)
network := "testnet"

# Build and compile the Move contract
build:
    aptos move compile --dev

# Run tests
test:
    aptos move test --dev

# Initialize a new account for deployment
init-account:
    aptos init --network {{network}}

# Fund the account with faucet (devnet only)
fund:
    aptos account fund-with-faucet --profile default --url https://fullnode.devnet.aptoslabs.com --faucet-url https://faucet.devnet.aptoslabs.com

# Deploy the contract
deploy:
    aptos move deploy-object --address-name money_pot --assume-yes

# Deploy with specific profile
deploy-profile profile:
    aptos move deploy-object --profile {{profile}} --address-name money_pot --assume-yes

# Upgrade existing contract
upgrade object-address:
    aptos move upgrade-object --address-name money_pot --object-address {{object-address}} --assume-yes

# Upgrade with specific profile
upgrade-profile profile object-address:
    aptos move upgrade-object --profile {{profile}} --address-name money_pot --object-address {{object-address}} --assume-yes

# Get account info
account-info:
    aptos account list --profile money-dev

# Get account balance
balance:
    aptos account list --profile money-dev --query balance

# Create a new pot (example usage)
create-pot amount duration-seconds fee one-fa-address *ARGS:
    aptos move run --profile money-dev --url https://fullnode.testnet.aptoslabs.com --function-id {{get-object-address}}::money_pot_manager::create_pot_entry --args u64:{{amount}} u64:{{duration-seconds}} u64:{{fee}} address: {{one-fa-address}} {{ARGS}} 

# Attempt a pot (example usage)
attempt-pot pot-id:
    aptos move run --profile money-dev --url https://fullnode.testnet.aptoslabs.com --function-id {{get-object-address}}::money_pot_manager::attempt_pot_entry --args u64:{{pot-id}}

# Get all pots
get-pots:
    aptos move view --url https://fullnode.testnet.aptoslabs.com --function-id {{get-object-address}}::money_pot_manager::get_pots

# Get active pots
get-active-pots:
    aptos move view --url https://fullnode.testnet.aptoslabs.com --function-id {{get-object-address}}::money_pot_manager::get_active_pots

# Get pot by ID
get-pot pot-id:
    aptos move view --url https://fullnode.testnet.aptoslabs.com --function-id {{get-object-address}}::money_pot_manager::get_pot --args u64:{{pot-id}}

# Get attempt by ID
get-attempt attempt-id:
    aptos move view --url https://fullnode.testnet.aptoslabs.com --function-id {{get-object-address}}::money_pot_manager::get_attempt --args u64:{{attempt-id}}

# Helper to get the deployed object address
get-object-address := "0xe8769b0b3019185cd0261396a9d6159898a9c12928b88780176e5b701fb5c141"

# Full deployment workflow
deploy-full:
    just build
    just init-account
    just fund
    just deploy
    @echo "Deployment complete! Update get-object-address with your contract address"

# Clean build artifacts
clean:
    rm -rf build/

# Help
help:
    @echo "Available commands:"
    @echo "  build              - Compile the Move contract"
    @echo "  test               - Run unit tests"
    @echo "  init-account       - Initialize new deployment account"
    @echo "  fund               - Fund account with faucet (devnet only)"
    @echo "  deploy             - Deploy the contract"
    @echo "  upgrade <addr>     - Upgrade existing contract"
    @echo "  account-info       - Show account information"
    @echo "  balance            - Show account balance"
    @echo "  create-pot <args>  - Create a new money pot"
    @echo "  attempt-pot <id>    - Attempt to solve a pot"
    @echo "  get-pots           - List all pots"
    @echo "  get-active-pots    - List active pots"
    @echo "  get-pot <id>       - Get pot details"
    @echo "  get-attempt <id>   - Get attempt details"
    @echo "  deploy-full        - Complete deployment workflow"
    @echo "  clean              - Clean build artifacts"
    @echo ""
    @echo "Example usage:"
    @echo "  just deploy-full"
    @echo "  just create-pot 1000000 3600 100000 0x123..."
    @echo "  just attempt-pot 0"
