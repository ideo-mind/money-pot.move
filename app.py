import os
import asyncio
from typing import Optional

from dotenv import load_dotenv
load_dotenv()


from aptos_sdk.account import Account
from aptos_sdk.async_client import RestClient as AsyncRestClient
from aptos_sdk.authenticator import Authenticator
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
        "MODULE_ADDRESS",
        "0xe8769b0b3019185cd0261396a9d6159898a9c12928b88780176e5b701fb5c141",
    )
)
MODULE_QN = f"{MODULE_ADDR}::money_pot_manager"


def load_main_account_from_env() -> Account:
    private_key_hex = os.getenv("APTOS_PRIVATE_KEY")
    if not private_key_hex:
        raise RuntimeError("APTOS_PRIVATE_KEY is not set")
    return Account.load_key(bytes.fromhex(private_key_hex))


async def submit_entry(
    client: AsyncRestClient, account: Account, entry: EntryFunction
) -> str:
    payload = TransactionPayload(entry)
    raw_txn = await client.create_bcs_transaction(account, payload)
    signed: SignedTransaction = account.sign(raw_txn)
    tx_hash = await client.submit_bcs_transaction(signed)
    await client.wait_for_transaction(tx_hash)
    return tx_hash


async def view_function(client: AsyncRestClient, func_qn: str, args: list[bytes]) -> list:
    return await client.view(func_qn, [], args)


async def create_pot(
    client: AsyncRestClient,
    creator: Account,
    amount: int,
    duration_seconds: int,
    fee: int,
    one_fa_address: AccountAddress,
) -> None:
    entry = EntryFunction.natural(
        MODULE_QN,
        "create_pot_entry",
        [],
        [
            TransactionArgument.u64(amount),
            TransactionArgument.u64(duration_seconds),
            TransactionArgument.u64(fee),
            TransactionArgument.address(one_fa_address),
        ],
    )
    await submit_entry(client, creator, entry)


async def attempt_pot(client: AsyncRestClient, hunter: Account, pot_id: int) -> None:
    entry = EntryFunction.natural(
        MODULE_QN,
        "attempt_pot_entry",
        [],
        [TransactionArgument.u64(pot_id)],
    )
    await submit_entry(client, hunter, entry)


async def attempt_completed(
    client: AsyncRestClient, oracle: Account, attempt_id: int, status: bool
) -> None:
    entry = EntryFunction.natural(
        MODULE_QN,
        "attempt_completed",
        [],
        [
            TransactionArgument.u64(attempt_id),
            TransactionArgument.bool(status),
        ],
    )
    await submit_entry(client, oracle, entry)


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

    # Create pot
    await create_pot(client, main_acct, amount, duration_seconds, fee, one_fa_addr)

    # Fetch latest pot_id
    pots = await get_pots(client)
    if not pots:
        raise RuntimeError("No pots found after creation")
    pot_id = max(pots)

    # Attempt as hunter using same env account
    await attempt_pot(client, main_acct, pot_id)

    # We need attempt_id; the Move code increments monotonically. Use latest attempt id by probing sequentially via view on a small range.
    # Simple heuristic: check last few ids
    latest_attempt_id: Optional[int] = None
    for attempt_id in range(10):
        try:
            await get_attempt(client, attempt_id)
            latest_attempt_id = attempt_id
        except Exception:
            pass
    if latest_attempt_id is None:
        # Fallback: assume 0 on fresh deployment
        latest_attempt_id = 0

    # First mark as failed
    await attempt_completed(client, main_acct, latest_attempt_id, False)

    # Second attempt again, then mark success
    await attempt_pot(client, main_acct, pot_id)

    # Update latest attempt id again
    next_attempt_id = latest_attempt_id + 1
    await attempt_completed(client, main_acct, next_attempt_id, True)

    print(
        f"Done. Pot {pot_id} created with 1FA {one_fa_addr}, attempts {latest_attempt_id} failed and {next_attempt_id} succeeded."
    )


if __name__ == "__main__":
    asyncio.run(main())


