script {
    use std::debug;
    use aptos_framework::timestamp;
    use money_pot::money_pot_manager;

    /// Script to expire a pot with detailed validation and logging
    /// This script provides comprehensive logging similar to the Python script
    fun expire_pot_with_detailed_logging(account: &signer, pot_id: u64) {
        debug::print(&b"[EXPIRE_POTS] Detailed pot expiration check:");
        debug::print(&pot_id);
        
        let current_time = timestamp::now_seconds();
        
        // Get pot details
        let pot = money_pot_manager::get_pot(pot_id);
        let pot_is_active = money_pot_manager::get_pot_is_active(&pot);
        let pot_expires_at = money_pot_manager::get_pot_expires_at(&pot);
        let pot_creator = money_pot_manager::get_pot_creator(&pot);
        let pot_total_amount = money_pot_manager::get_pot_total_amount(&pot);
        
        debug::print(&b"[EXPIRE_POTS] Pot details:");
        debug::print(&b"  - Creator:");
        debug::print(&pot_creator);
        debug::print(&b"  - Total amount:");
        debug::print(&pot_total_amount);
        debug::print(&b"  - Is active:");
        debug::print(&pot_is_active);
        debug::print(&b"  - Expires at:");
        debug::print(&pot_expires_at);
        debug::print(&b"  - Current time:");
        debug::print(&current_time);
        
        if (pot_is_active && current_time >= pot_expires_at) {
            let expired_seconds_ago = current_time - pot_expires_at;
            debug::print(&b"[EXPIRE_POTS] Pot is expired (expired");
            debug::print(&expired_seconds_ago);
            debug::print(&b"seconds ago)");
            debug::print(&b"[EXPIRE_POTS] Expiring immediately...");
            
            money_pot_manager::expire_pot(account, pot_id);
            debug::print(&b"[EXPIRE_POTS] Pot expiration completed successfully!");
        } else {
            debug::print(&b"[EXPIRE_POTS] Pot is still active or not expired");
        };
        
        debug::print(&b"[EXPIRE_POTS] Pot expiration validation completed");
    }
}
