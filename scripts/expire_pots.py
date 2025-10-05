#!/usr/bin/env python3
"""
Script to expire all expired pots in the Money Pot contract.
This script fetches all active pots and attempts to expire those that have passed their expiration time.
"""

import json
import subprocess
import sys
import time
from typing import List, Dict, Any

def run_aptos_command(command: List[str]) -> Dict[str, Any]:
    """Run an aptos CLI command and return the parsed JSON output."""
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error running command {' '.join(command)}: {e}")
        print(f"stderr: {e.stderr}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON output: {e}")
        print(f"Raw output: {result.stdout}")
        sys.exit(1)

def get_active_pots(rpc_url: str, contract_address: str) -> List[int]:
    """Get all active pot IDs from the contract."""
    command = [
        "aptos", "move", "view",
        "--url", rpc_url,
        "--function-id", f"{contract_address}::money_pot_manager::get_active_pots"
    ]
    
    result = run_aptos_command(command)
    
    # Extract pot IDs from the Result wrapper and convert strings to integers
    if isinstance(result, dict) and "Result" in result:
        pot_ids_raw = result["Result"]
        if isinstance(pot_ids_raw, list) and len(pot_ids_raw) > 0:
            # Convert string IDs to integers
            return [int(pot_id) for pot_id in pot_ids_raw[0]]
    
    print(f"Unexpected result format: {result}")
    return []

def get_pot_details(rpc_url: str, contract_address: str, pot_id: int) -> Dict[str, Any]:
    """Get detailed information about a specific pot."""
    command = [
        "aptos", "move", "view",
        "--url", rpc_url,
        "--function-id", f"{contract_address}::money_pot_manager::get_pot",
        "--args", f"u64:{pot_id}"
    ]
    
    result = run_aptos_command(command)
    
    # Extract pot details from the Result wrapper
    if isinstance(result, dict) and "Result" in result:
        pot_data = result["Result"]
        # If it's a list with one element, extract that element
        if isinstance(pot_data, list) and len(pot_data) > 0:
            return pot_data[0]
        return pot_data
    
    print(f"Unexpected pot details format: {result}")
    return {}

def expire_pot(rpc_url: str, contract_address: str, profile: str, pot_id: int) -> tuple[bool, str]:
    """Attempt to expire a specific pot. Returns (success, tx_hash)."""
    command = [
        "aptos", "move", "run",
        "--profile", profile,
        "--url", rpc_url,
        "--function-id", f"{contract_address}::money_pot_manager::expire_pot",
        "--args", f"u64:{pot_id}"
    ]
    
    try:
        print(f"🔄 Expiring pot {pot_id}...")
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        
        # Parse the transaction hash from the output
        tx_hash = "unknown"
        try:
            result_json = json.loads(result.stdout)
            if "hash" in result_json:
                tx_hash = result_json["hash"]
            elif "transaction" in result_json and "hash" in result_json["transaction"]:
                tx_hash = result_json["transaction"]["hash"]
        except (json.JSONDecodeError, KeyError):
            # Try to extract hash from text output
            lines = result.stdout.split('\n')
            for line in lines:
                if 'hash' in line.lower() and len(line.split()) > 1:
                    tx_hash = line.split()[-1]
                    break
        
        print(f"✅ Pot {pot_id} expired successfully!")
        print(f"   📝 TX Hash: {tx_hash}")
        print(f"   🔗 Explorer: https://explorer.aptoslabs.com/txn/{tx_hash}")
        print("-" * 40)
        return True, tx_hash
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to expire pot {pot_id}: {e.stderr}")
        return False, "failed"

def get_current_timestamp() -> int:
    """Get current Unix timestamp."""
    return int(time.time())

def main():
    """Main function to expire all expired pots."""
    # Get configuration from environment variables
    rpc_url = os.environ.get("RPC_URL", "https://fullnode.devnet.aptoslabs.com")
    contract_address = os.environ.get("MONEY_POT_ADDRESS", "0x111111")
    profile = os.environ.get("APTOS_PROFILE", "admin")
    
    print(f"🔍 Fetching active pots from contract {contract_address}...")
    
    # Get all active pots
    active_pot_ids = get_active_pots(rpc_url, contract_address)
    print(f"📋 Found {len(active_pot_ids)} active pots")
    
    if not active_pot_ids:
        print("✨ No active pots to check for expiration")
        return
    
    current_time = get_current_timestamp()
    
    # Check each pot for expiration and expire immediately if expired
    print(f"⏰ Current timestamp: {current_time}")
    print("🔍 Checking pots for expiration...")
    print("=" * 60)
    
    success_count = 0
    successful_txs = []
    failed_pots = []
    active_count = 0
    
    for i, pot_id in enumerate(active_pot_ids, 1):
        pot_details = get_pot_details(rpc_url, contract_address, pot_id)
        
        # Extract pot information
        expires_at = int(pot_details.get("expires_at", 0))
        is_active = pot_details.get("is_active", False)
        creator = pot_details.get("creator", "unknown")
        total_amount = pot_details.get("total_amount", 0)
        
        print(f"\n[{i}/{len(active_pot_ids)}] Pot {pot_id}: expires_at={expires_at}, active={is_active}, creator={creator}, amount={total_amount}")
        
        if is_active and current_time >= expires_at:
            expired_seconds_ago = current_time - expires_at
            print(f"  ⏰ Pot {pot_id} is expired (expired {expired_seconds_ago} seconds ago)")
            print(f"  🚀 Expiring immediately...")
            
            success, tx_hash = expire_pot(rpc_url, contract_address, profile, pot_id)
            if success:
                success_count += 1
                successful_txs.append((pot_id, tx_hash))
            else:
                failed_pots.append(pot_id)
        else:
            active_count += 1
            print(f"  ✅ Pot {pot_id} is still active")
        
        # Show progress
        print(f"Progress: {success_count} expired, {active_count} still active, {len(failed_pots)} failed")
    
    if success_count == 0 and active_count == len(active_pot_ids):
        print("\n✨ No expired pots found - all pots are still active")
        return
    
    print(f"\n📊 Summary:")
    print(f"  Total pots checked: {len(active_pot_ids)}")
    print(f"  Successfully expired: {success_count}")
    print(f"  Still active: {active_count}")
    print(f"  Failed to expire: {len(failed_pots)}")
    
    if successful_txs:
        print(f"\n✅ Successful transactions:")
        for pot_id, tx_hash in successful_txs:
            print(f"  Pot {pot_id}: {tx_hash}")
    
    if failed_pots:
        print(f"\n❌ Failed pots:")
        for pot_id in failed_pots:
            print(f"  Pot {pot_id}")

if __name__ == "__main__":
    import os
    main()
