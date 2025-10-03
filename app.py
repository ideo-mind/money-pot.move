import os
import asyncio
from typing import Optional, Dict, Any

from dotenv import load_dotenv
load_dotenv()

from aptos_sdk.account import Account
from aptos_sdk.async_client import RestClient as AsyncRestClient
from aptos_sdk.bcs import Serializer
from aptos_sdk.transactions import (
    EntryFunction,
    TransactionArgument,
    TransactionPayload,
    SignedTransaction,
)
from aptos_sdk.account_address import AccountAddress


NODE_URL = os.getenv("RPC_URL", "https://fullnode.testnet.aptoslabs.com/v1")

# Module object address from build/justfile
MODULE_ADDR = (
    os.getenv(
        "MONEY_POT_ADDRESS",
        "0xea89ef9798a210009339ea6105c2008d8e154f8b5ae1807911c86320ea03ff3f",
    )
)
MODULE_QN = f"{MODULE_ADDR}::money_pot_manager"


def load_main_account_from_env() -> Account:
    """Load account from APTOS_PRIVATE_KEY environment variable"""
    private_key = os.getenv("APTOS_PRIVATE_KEY")
    if not private_key:
        raise RuntimeError("APTOS_PRIVATE_KEY is not set")
    return Account.load_key(private_key)


def load_hunter_account_from_env() -> Account:
    """Load hunter account from HUNTER_PRIVATE_KEY environment variable"""
    private_key = os.getenv("HUNTER_PRIVATE_KEY")
    if not private_key:
        raise RuntimeError("HUNTER_PRIVATE_KEY is not set")
    return Account.load_key(private_key)


async def create_account(client: AsyncRestClient, creator: Account, new_account: Account) -> str:
    """Create a new account"""
    from aptos_sdk.transactions import EntryFunction, TransactionPayload
    
    entry = EntryFunction.natural(
        "0x1::aptos_account",
        "create_account",
        [],
        [
            TransactionArgument(new_account.account_address, lambda s, addr: addr.serialize(s)),
        ],
    )
    
    payload = TransactionPayload(entry)
    return await submit_transaction(client, creator, payload)


async def fund_account(client: AsyncRestClient, sender: Account, receiver: AccountAddress, amount: int) -> str:
    """Fund an account with APT tokens"""
    from aptos_sdk.transactions import EntryFunction, TransactionPayload
    
    entry = EntryFunction.natural(
        "0x1::aptos_account",
        "transfer",
        [],
        [
            TransactionArgument(receiver, lambda s, addr: addr.serialize(s)),
            TransactionArgument(amount, Serializer.u64),
        ],
    )
    
    payload = TransactionPayload(entry)
    return await submit_transaction(client, sender, payload)


async def fund_fungible_asset(client: AsyncRestClient, sender: Account, receiver: AccountAddress, token_address: str, amount: int) -> str:
    """Fund an account with fungible assets"""
    from aptos_sdk.transactions import EntryFunction, TransactionPayload, TypeTag, StructTag
    from aptos_sdk.account_address import AccountAddress
    
    token_addr = AccountAddress.from_str(token_address)
    
    # Create the type argument for the fungible asset
    type_arg = TypeTag(StructTag(
        AccountAddress.from_str("0x1"),
        "fungible_asset",
        "FungibleAsset",
        [TypeTag(StructTag(token_addr, "", "", []))]
    ))
    
    entry = EntryFunction.natural(
        "0x1::primary_fungible_store",
        "transfer",
        [type_arg],
        [
            TransactionArgument(receiver, lambda s, addr: addr.serialize(s)),
            TransactionArgument(amount, Serializer.u64),
        ],
    )
    
    payload = TransactionPayload(entry)
    return await submit_transaction(client, sender, payload)


async def submit_transaction(client: AsyncRestClient, account: Account, payload: TransactionPayload) -> str:
    """Submit a transaction and return the hash"""
    # Create and sign the transaction using the SDK method
    signed_txn = await client.create_bcs_signed_transaction(account, payload)
    
    # Submit and wait
    result = await client.submit_and_wait_for_bcs_transaction(signed_txn)
    return result["hash"]


async def get_transaction_events(client: AsyncRestClient, tx_hash: str) -> list[Dict[str, Any]]:
    """Get events from a transaction"""
    tx = await client.transaction_by_hash(tx_hash)
    return tx.get("events", [])


def extract_pot_id_from_events(events: list[Dict[str, Any]]) -> Optional[int]:
    """Extract pot_id from PotEvent with event_type 'created'"""
    for event in events:
        if event.get("type") == f"{MODULE_ADDR}::money_pot_manager::PotEvent":
            data = event.get("data", {})
            event_type_hex = data.get("event_type", "")
            if event_type_hex:
                try:
                    event_type = bytes.fromhex(event_type_hex[2:]).decode()  # Remove '0x' prefix
                    if event_type == "created":
                        return int(data.get("id", 0))
                except:
                    continue
    return None


def extract_attempt_id_from_events(events: list[Dict[str, Any]]) -> Optional[int]:
    """Extract attempt_id from PotEvent with event_type 'attempted'"""
    for event in events:
        if event.get("type") == f"{MODULE_ADDR}::money_pot_manager::PotEvent":
            data = event.get("data", {})
            event_type_hex = data.get("event_type", "")
            if event_type_hex:
                try:
                    event_type = bytes.fromhex(event_type_hex[2:]).decode()  # Remove '0x' prefix
                    if event_type == "attempted":
                        return int(data.get("id", 0))
                except:
                    continue
    return None


async def view_function(client: AsyncRestClient, func_qn: str, args: list[bytes]) -> list:
    return await client.view(func_qn, [], args)


async def create_pot(
    client: AsyncRestClient,
    creator: Account,
    amount: int,
    duration_seconds: int,
    fee: int,
    one_fa_address: AccountAddress,
) -> str:
    """Create pot and return transaction hash"""
    # Use TransactionArgument objects with correct encoders
    entry = EntryFunction.natural(
        MODULE_QN,
        "create_pot_entry",
        [],
        [
            TransactionArgument(amount, Serializer.u64),
            TransactionArgument(duration_seconds, Serializer.u64),
            TransactionArgument(fee, Serializer.u64),
            TransactionArgument(one_fa_address, lambda s, addr: addr.serialize(s)),
        ],
    )
    
    payload = TransactionPayload(entry)
    return await submit_transaction(client, creator, payload)


async def attempt_pot(client: AsyncRestClient, hunter: Account, pot_id: int) -> str:
    """Attempt pot and return transaction hash"""
    entry = EntryFunction.natural(
        MODULE_QN,
        "attempt_pot_entry",
        [],
        [TransactionArgument(pot_id, Serializer.u64)],
    )
    
    payload = TransactionPayload(entry)
    return await submit_transaction(client, hunter, payload)


async def attempt_completed(
    client: AsyncRestClient, oracle: Account, attempt_id: int, status: bool
) -> str:
    """Mark attempt as completed and return transaction hash"""
    entry = EntryFunction.natural(
        MODULE_QN,
        "attempt_completed",
        [],
        [
            TransactionArgument(attempt_id, Serializer.u64),
            TransactionArgument(status, Serializer.bool),
        ],
    )
    
    payload = TransactionPayload(entry)
    return await submit_transaction(client, oracle, payload)


async def get_active_pots(client: AsyncRestClient) -> list[int]:
    res = await view_function(client, f"{MODULE_QN}::get_active_pots", [])
    return [int(x) for x in res]


async def get_pots(client: AsyncRestClient) -> list[int]:
    res = await view_function(client, f"{MODULE_QN}::get_pots", [])
    return [int(x) for x in res]


async def get_attempt(client: AsyncRestClient, attempt_id: int) -> dict:
    ser = Serializer()
    ser.u64(attempt_id)
    res = await view_function(client, f"{MODULE_QN}::get_attempt", [ser.output()])
    return res  # SDK returns decoded fields; keep generic


async def main() -> None:
    client = AsyncRestClient(NODE_URL)

    # Load accounts from environment variables
    main_acct = load_main_account_from_env()
    hunter_acct = load_hunter_account_from_env()
    hunter_addr = hunter_acct.account_address

    # Parameters
    amount = int(os.getenv("POT_AMOUNT", 1e6))
    duration_seconds = int(os.getenv("POT_DURATION", "360"))
    fee = int(os.getenv("POT_FEE", amount/100))

    print(f"Using hunter account: {hunter_addr}")

    print(f"Creating pot with amount={amount}, duration={duration_seconds}, fee={fee}, 1FA={hunter_addr}")

    # Create pot and get pot_id from events
    create_tx_hash = await create_pot(client, main_acct, amount, duration_seconds, fee, hunter_addr)
    print(f"Pot creation tx: {create_tx_hash}")
    
    create_events = await get_transaction_events(client, create_tx_hash)
    print(f"Creation events: {create_events}")
    pot_id = extract_pot_id_from_events(create_events)
    if pot_id is None:
        raise RuntimeError("Could not extract pot_id from creation events")
    print(f"Created pot with ID: {pot_id}")

    # Attempt as hunter using the configured hunter account and get attempt_id from events
    attempt_tx_hash = await attempt_pot(client, hunter_acct, pot_id)
    print(f"First attempt tx: {attempt_tx_hash}")
    
    attempt_events = await get_transaction_events(client, attempt_tx_hash)
    attempt_id = extract_attempt_id_from_events(attempt_events)
    if attempt_id is None:
        raise RuntimeError("Could not extract attempt_id from attempt events")
    print(f"Created attempt with ID: {attempt_id}")

    # First mark as failed
    print(f"Marking attempt {attempt_id} as failed...")
    fail_tx_hash = await attempt_completed(client, main_acct, attempt_id, False)
    print(f"Mark failed tx: {fail_tx_hash}")

    # Second attempt again, then mark success
    print(f"Making second attempt on pot {pot_id}...")
    attempt2_tx_hash = await attempt_pot(client, hunter_acct, pot_id)
    print(f"Second attempt tx: {attempt2_tx_hash}")
    
    attempt2_events = await get_transaction_events(client, attempt2_tx_hash)
    attempt2_id = extract_attempt_id_from_events(attempt2_events)
    if attempt2_id is None:
        raise RuntimeError("Could not extract attempt_id from second attempt events")
    print(f"Created second attempt with ID: {attempt2_id}")

    # Mark second attempt as successful
    print(f"Marking attempt {attempt2_id} as successful...")
    success_tx_hash = await attempt_completed(client, main_acct, attempt2_id, True)
    print(f"Mark success tx: {success_tx_hash}")

    print(f"\nDone! Summary:")
    print(f"- Pot {pot_id} created with 1FA {hunter_addr}")
    print(f"- First attempt {attempt_id} marked as failed")
    print(f"- Second attempt {attempt2_id} marked as successful")


if __name__ == "__main__":
    asyncio.run(main())