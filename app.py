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
    private_key = os.getenv("APTOS_PRIVATE_KEY")
    if not private_key:
        raise RuntimeError("APTOS_PRIVATE_KEY is not set")
    return Account.load_key(private_key)


async def submit_transaction(client: AsyncRestClient, account: Account, payload: TransactionPayload) -> str:
    """Submit a transaction and return the hash"""
    # Create the transaction
    raw_txn = await client.create_bcs_transaction(account, payload)
    
    # Serialize the transaction for signing
    serializer = Serializer()
    raw_txn.serialize(serializer)
    
    # Sign the serialized transaction
    signature = account.sign(serializer.output())
    
    # Create signed transaction
    signed_txn = SignedTransaction(raw_txn, signature)
    
    # Submit and wait
    result = await client.submit_and_wait_for_bcs_transaction(signed_txn)
    return result["hash"]


async def get_transaction_events(client: AsyncRestClient, tx_hash: str) -> list[Dict[str, Any]]:
    """Get events from a transaction"""
    tx = await client.get_transaction_by_hash(tx_hash)
    return tx.get("events", [])


def extract_pot_id_from_events(events: list[Dict[str, Any]]) -> Optional[int]:
    """Extract pot_id from PotEvent with event_type 'created'"""
    for event in events:
        if event.get("type") == f"{MODULE_QN}::PotEvent":
            data = event.get("data", {})
            if data.get("event_type") == "created":
                return int(data.get("id", 0))
    return None


def extract_attempt_id_from_events(events: list[Dict[str, Any]]) -> Optional[int]:
    """Extract attempt_id from PotEvent with event_type 'attempted'"""
    for event in events:
        if event.get("type") == f"{MODULE_QN}::PotEvent":
            data = event.get("data", {})
            if data.get("event_type") == "attempted":
                return int(data.get("id", 0))
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
            TransactionArgument(one_fa_address, Serializer.struct),
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

    # Load orchestrator (creator and hunter) from env private key
    main_acct = load_main_account_from_env()

    # Generate non-persisted 1FA account address
    one_fa_tmp = Account.generate()
    one_fa_addr = one_fa_tmp.address()

    # Parameters
    amount = int(os.getenv("POT_AMOUNT", "1000000"))
    duration_seconds = int(os.getenv("POT_DURATION", "3600"))
    fee = int(os.getenv("POT_FEE", "1000"))

    print(f"Creating pot with amount={amount}, duration={duration_seconds}, fee={fee}, 1FA={one_fa_addr}")

    # Create pot and get pot_id from events
    create_tx_hash = await create_pot(client, main_acct, amount, duration_seconds, fee, one_fa_addr)
    print(f"Pot creation tx: {create_tx_hash}")
    
    create_events = await get_transaction_events(client, create_tx_hash)
    pot_id = extract_pot_id_from_events(create_events)
    if pot_id is None:
        raise RuntimeError("Could not extract pot_id from creation events")
    print(f"Created pot with ID: {pot_id}")

    # Attempt as hunter using same env account and get attempt_id from events
    attempt_tx_hash = await attempt_pot(client, main_acct, pot_id)
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
    attempt2_tx_hash = await attempt_pot(client, main_acct, pot_id)
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
    print(f"- Pot {pot_id} created with 1FA {one_fa_addr}")
    print(f"- First attempt {attempt_id} marked as failed")
    print(f"- Second attempt {attempt2_id} marked as successful")


if __name__ == "__main__":
    asyncio.run(main())