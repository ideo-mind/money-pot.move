script {
    use std::debug;
    use aptos_framework::timestamp;
    use 0xea89ef9798a210009339ea6105c2008d8e154f8b5ae1807911c86320ea03ff3f::money_pot_manager;

    /// Script to expire multiple pots by their IDs (up to 3 pots)
    /// Usage: aptos move run-script --compiled-script-path expire_multiple_pots.mv --args u64:123 u64:456 u64:789
    fun expire_multiple_pots(
        account: &signer,
        pot_id_1: u64, 
        pot_id_2: u64, 
        pot_id_3: u64
    ) {
        debug::print(&b"[EXPIRE_POTS] Starting batch expiration of multiple pots");
        
        let current_time = timestamp::now_seconds();
        
        // Process first pot
        if (pot_id_1 != 0) {
            debug::print(&b"[EXPIRE_POTS] Processing pot 1:");
            debug::print(&pot_id_1);
            
            let pot1 = money_pot_manager::get_pot(pot_id_1);
            let pot1_is_active = money_pot_manager::get_pot_is_active(&pot1);
            let pot1_expires_at = money_pot_manager::get_pot_expires_at(&pot1);
            
            if (pot1_is_active && current_time >= pot1_expires_at) {
                debug::print(&b"[EXPIRE_POTS] Pot 1 is expired, expiring...");
                money_pot_manager::expire_pot(account, pot_id_1);
                debug::print(&b"[EXPIRE_POTS] Pot 1 expired successfully");
            } else {
                debug::print(&b"[EXPIRE_POTS] Pot 1 skipped (not expired or inactive)");
            };
        };
        
        // Process second pot
        if (pot_id_2 != 0) {
            debug::print(&b"[EXPIRE_POTS] Processing pot 2:");
            debug::print(&pot_id_2);
            
            let pot2 = money_pot_manager::get_pot(pot_id_2);
            let pot2_is_active = money_pot_manager::get_pot_is_active(&pot2);
            let pot2_expires_at = money_pot_manager::get_pot_expires_at(&pot2);
            
            if (pot2_is_active && current_time >= pot2_expires_at) {
                debug::print(&b"[EXPIRE_POTS] Pot 2 is expired, expiring...");
                money_pot_manager::expire_pot(account, pot_id_2);
                debug::print(&b"[EXPIRE_POTS] Pot 2 expired successfully");
            } else {
                debug::print(&b"[EXPIRE_POTS] Pot 2 skipped (not expired or inactive)");
            };
        };
        
        // Process third pot
        if (pot_id_3 != 0) {
            debug::print(&b"[EXPIRE_POTS] Processing pot 3:");
            debug::print(&pot_id_3);
            
            let pot3 = money_pot_manager::get_pot(pot_id_3);
            let pot3_is_active = money_pot_manager::get_pot_is_active(&pot3);
            let pot3_expires_at = money_pot_manager::get_pot_expires_at(&pot3);
            
            if (pot3_is_active && current_time >= pot3_expires_at) {
                debug::print(&b"[EXPIRE_POTS] Pot 3 is expired, expiring...");
                money_pot_manager::expire_pot(account, pot_id_3);
                debug::print(&b"[EXPIRE_POTS] Pot 3 expired successfully");
            } else {
                debug::print(&b"[EXPIRE_POTS] Pot 3 skipped (not expired or inactive)");
            };
        };
        
        debug::print(&b"[EXPIRE_POTS] Batch expiration completed");
    }
}
