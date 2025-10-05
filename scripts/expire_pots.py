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

async def get_pot_details(client: AsyncRestClient, pot_id: int) -> Dict[str, Any]:
    """Get detailed information about a specific pot."""
    res = await client.view(f"{MODULE_QN}::get_pot", [], [str(pot_id)])
    return res if isinstance(res, dict) else {}

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

def get_current_timestamp() -> int:
    """Get current Unix timestamp."""
    return int(time.time())

async def expire_pots_batch(client: AsyncRestClient, account: Account, pot_ids: List[int]) -> List[Tuple[int, str]]:
    """Expire multiple pots in batches of 3 using the Move script."""
    successful_txs = []
    
    # Process pots in batches of 3
    for i in range(0, len(pot_ids), 3):
        batch = pot_ids[i:i+3]
        # Pad with 0s if batch is smaller than 3
        while len(batch) < 3:
            batch.append(0)
        
        try:
            print(f"🚀 Expiring batch {i//3 + 1}: pots {batch[:3] if batch[2] != 0 else batch[:2] if batch[1] != 0 else [batch[0]]}")
            
            entry = EntryFunction.natural(
                MODULE_QN,
                "expire_multiple_pots",
                [],
                [
                    TransactionArgument(batch[0], Serializer.u64),
                    TransactionArgument(batch[1], Serializer.u64),
                    TransactionArgument(batch[2], Serializer.u64),
                ],
            )
            
            payload = TransactionPayload(entry)
            tx_hash = await submit_transaction(client, account, payload)
            
            print(f"✅ Batch expired successfully!")
            print(f"   📝 TX Hash: {tx_hash}")
            print(f"   🔗 Explorer: https://explorer.aptoslabs.com/txn/{tx_hash}")
            print("-" * 40)
            
            # Add all non-zero pot IDs to successful list
            for pot_id in batch:
                if pot_id != 0:
                    successful_txs.append((pot_id, tx_hash))
                    
        except Exception as e:
            print(f"❌ Failed to expire batch: {e}")
            # Try individual expiration for this batch
            for pot_id in batch:
                if pot_id != 0:
                    try:
                        success, tx_hash = await expire_pot(client, account, pot_id)
                        if success:
                            successful_txs.append((pot_id, tx_hash))
                    except Exception as individual_error:
                        print(f"❌ Failed to expire pot {pot_id} individually: {individual_error}")
    
    return successful_txs

async def main():
    """Main function to expire all expired pots efficiently."""
    print(f"🔍 Fetching active pots from contract {MODULE_ADDR}...")
    
    # Initialize client and account
    client = AsyncRestClient(NODE_URL)
    account = load_account_from_env()
    
    # Get all active pots
    active_pot_ids = await get_active_pots(client)
    print(f"📋 Found {len(active_pot_ids)} active pots")
    
    if not active_pot_ids:
        print("✨ No active pots to check for expiration")
        return
    
    current_time = get_current_timestamp()
    print(f"⏰ Current timestamp: {current_time}")
    
    # Filter for expired pots efficiently
    print("🔍 Filtering for expired pots...")
    expired_pot_ids = []
    
    # Process in smaller batches to avoid overwhelming the RPC
    batch_size = 50
    for i in range(0, len(active_pot_ids), batch_size):
        batch = active_pot_ids[i:i+batch_size]
        print(f"Checking batch {i//batch_size + 1}/{(len(active_pot_ids) + batch_size - 1)//batch_size} ({len(batch)} pots)...")
        
        # Get pot details for this batch
        tasks = [get_pot_details(client, pot_id) for pot_id in batch]
        pot_details_list = await asyncio.gather(*tasks)
        
        for pot_id, pot_details in zip(batch, pot_details_list):
            expires_at = int(pot_details.get("expires_at", 0))
            is_active = pot_details.get("is_active", False)
            
            if is_active and expires_at > 0 and current_time >= expires_at:
                expired_pot_ids.append(pot_id)
    
    print(f"⏰ Found {len(expired_pot_ids)} expired pots")
    
    if not expired_pot_ids:
        print("✨ No expired pots found - all pots are still active")
        return
    
    print(f"🚀 Expiring {len(expired_pot_ids)} expired pots...")
    print("=" * 60)
    
    # Expire all expired pots using batch processing
    successful_txs = await expire_pots_batch(client, account, expired_pot_ids)
    
    print(f"\n📊 Summary:")
    print(f"  Total active pots checked: {len(active_pot_ids)}")
    print(f"  Expired pots found: {len(expired_pot_ids)}")
    print(f"  Successfully expired: {len(successful_txs)}")
    print(f"  Failed to expire: {len(expired_pot_ids) - len(successful_txs)}")
    
    if successful_txs:
        print(f"\n✅ Successful transactions:")
        for pot_id, tx_hash in successful_txs:
            print(f"  Pot {pot_id}: {tx_hash}")

if __name__ == "__main__":
    asyncio.run(main())
