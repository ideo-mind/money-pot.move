#!/usr/bin/env python3
"""
Script to expire all expired pots in the Money Pot contract.
This script fetches all active pots and attempts to expire those that have passed their expiration time.
"""

import os
import asyncio
import time
from typing import List, Dict, Any, Optional, Tuple
from dotenv import load_dotenv

from aptos_sdk.account import Account
from aptos_sdk.async_client import RestClient as AsyncRestClient
from aptos_sdk.bcs import Serializer
from aptos_sdk.transactions import (
    EntryFunction,
    TransactionArgument,
    TransactionPayload,
)
from aptos_sdk.account_address import AccountAddress

load_dotenv()

NODE_URL = os.getenv("RPC_URL", "https://fullnode.testnet.aptoslabs.com/v1")
MODULE_ADDR = os.getenv(
    "MONEY_POT_ADDRESS",
    "0xea89ef9798a210009339ea6105c2008d8e154f8b5ae1807911c86320ea03ff3f",
)
MODULE_QN = f"{MODULE_ADDR}::money_pot_manager"

def load_account_from_env() -> Account:
    """Load account from APTOS_PRIVATE_KEY environment variable"""
    private_key = os.getenv("APTOS_PRIVATE_KEY")
    if not private_key:
        raise RuntimeError("APTOS_PRIVATE_KEY is not set")
    return Account.load_key(private_key)

async def submit_transaction(client: AsyncRestClient, account: Account, payload: TransactionPayload) -> str:
    """Submit a transaction and return the hash"""
    signed_txn = await client.create_bcs_signed_transaction(account, payload)
    result = await client.submit_and_wait_for_bcs_transaction(signed_txn)
    return result["hash"]

async def get_active_pots(client: AsyncRestClient) -> List[int]:
    """Get all active pot IDs from the contract."""
    res = await client.view(f"{MODULE_QN}::get_active_pots", [], [])
    return [int(x) for x in res]

async def expire_pot(client: AsyncRestClient, account: Account, pot_id: int) -> Tuple[bool, str]:
    """Attempt to expire a specific pot. Returns (success, tx_hash)."""
    try:
        print(f"🔄 Expiring pot {pot_id}...")
        
        entry = EntryFunction.natural(
            MODULE_QN,
            "expire_pot",
            [],
            [TransactionArgument(pot_id, Serializer.u64)],
        )
        
        payload = TransactionPayload(entry)
        tx_hash = await submit_transaction(client, account, payload)
        
        print(f"✅ Pot {pot_id} expired successfully!")
        print(f"   📝 TX Hash: {tx_hash}")
        print(f"   🔗 Explorer: https://explorer.aptoslabs.com/txn/{tx_hash}")
        print("-" * 40)
        return True, tx_hash
    except Exception as e:
        print(f"❌ Failed to expire pot {pot_id}: {e}")
        return False, "failed"


async def expire_pots_individually(client: AsyncRestClient, account: Account, pot_ids: List[int]) -> List[Tuple[int, str]]:
    """Expire pots one by one."""
    successful_txs = []
    
    for pot_id in pot_ids:
        success, tx_hash = await expire_pot(client, account, pot_id)
        if success:
            successful_txs.append((pot_id, tx_hash))
    
    return successful_txs

async def main():
    """Main function to randomly try expiring active pots."""
    print(f"🔍 Fetching active pots from contract {MODULE_ADDR}...")
    
    # Initialize client and account
    client = AsyncRestClient(NODE_URL)
    account = load_account_from_env()
    
    # Get all active pots
    active_pot_ids = await get_active_pots(client)
    print(f"📋 Found {len(active_pot_ids)} active pots")
    
    if not active_pot_ids:
        print("✨ No active pots to try expiring")
        return
    
    print(f"🚀 Trying to expire {len(active_pot_ids)} active pots...")
    print("=" * 60)
    
    # Try to expire all active pots individually
    successful_txs = await expire_pots_individually(client, account, active_pot_ids)
    
    print(f"\n📊 Summary:")
    print(f"  Total active pots: {len(active_pot_ids)}")
    print(f"  Successfully expired: {len(successful_txs)}")
    print(f"  Failed to expire: {len(active_pot_ids) - len(successful_txs)}")
    
    if successful_txs:
        print(f"\n✅ Successful transactions:")
        for pot_id, tx_hash in successful_txs:
            print(f"  Pot {pot_id}: {tx_hash}")

if __name__ == "__main__":
    asyncio.run(main())
