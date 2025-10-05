script {
    use std::debug;
    use aptos_framework::timestamp;
    use 0xea89ef9798a210009339ea6105c2008d8e154f8b5ae1807911c86320ea03ff3f::money_pot_manager;

    /// Script to expire a single pot by ID
    /// Usage: aptos move run-script --compiled-script-path expire_pots.mv --args u64:123
    fun expire_single_pot(account: &signer, pot_id: u64) {
        debug::print(&b"[EXPIRE_POTS] Attempting to expire pot:");
        debug::print(&pot_id);
        
        // Get pot details for logging
        let pot = money_pot_manager::get_pot(pot_id);
        let pot_is_active = money_pot_manager::get_pot_is_active(&pot);
        let pot_expires_at = money_pot_manager::get_pot_expires_at(&pot);
        let current_time = timestamp::now_seconds();
        
        debug::print(&b"[EXPIRE_POTS] Pot details:");
        debug::print(&b"  - Active:");
        debug::print(&pot_is_active);
        debug::print(&b"  - Expires at:");
        debug::print(&pot_expires_at);
        debug::print(&b"  - Current time:");
        debug::print(&current_time);
        
        if (pot_is_active && current_time >= pot_expires_at) {
            debug::print(&b"[EXPIRE_POTS] Pot is expired, proceeding with expiration");
            money_pot_manager::expire_pot(account, pot_id);
            debug::print(&b"[EXPIRE_POTS] Pot expiration completed successfully");
        } else {
            debug::print(&b"[EXPIRE_POTS] Pot is not expired or not active");
        };
    }
}
