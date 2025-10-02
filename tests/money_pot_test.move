#[test_only]
module money_pot::money_pot_test {
    use aptos_framework::timestamp;
    use aptos_framework::account;
    use std::vector;

    use money_pot::money_pot_manager;

    // Test accounts
    const CREATOR: address = @0x1;
    const HUNTER: address = @0x2;
    const ORACLE: address = @0x3;

    #[test]
    fun test_create_pot() {
        let creator = account::create_account_for_test(CREATOR);
        let hunter = account::create_account_for_test(HUNTER);
        let oracle = account::create_account_for_test(ORACLE);


        // Initialize the module
        money_pot_manager::test_init(&creator);

        // Create a pot
        let pot_id = money_pot_manager::test_create_pot(&creator, 1000000, 3600, 100000, HUNTER);
        
        // Verify pot was created
        assert!(pot_id == 0, 0);
        
        // Get pot details
        let pot = money_pot_manager::test_get_pot(pot_id, CREATOR);
        assert!(money_pot_manager::get_pot_id(&pot) == 0, 1);
        assert!(money_pot_manager::get_pot_creator(&pot) == CREATOR, 2);
        assert!(money_pot_manager::get_pot_fee(&pot) == 100000, 4);
        assert!(money_pot_manager::get_pot_is_active(&pot) == true, 5);
        assert!(money_pot_manager::get_pot_attempts_count(&pot) == 0, 6);
    }

    #[test]
    fun test_attempt_pot() {
        let creator = account::create_account_for_test(CREATOR);
        let hunter = account::create_account_for_test(HUNTER);
        let oracle = account::create_account_for_test(ORACLE);


        // Initialize the module
        money_pot_manager::test_init(&creator);

        // Create a pot
        let pot_id = money_pot_manager::test_create_pot(&creator, 1000000, 3600, 100000, HUNTER);
        
        // Attempt the pot
        let attempt_id = money_pot_manager::test_attempt_pot(&hunter, pot_id, CREATOR);
        
        // Verify attempt was created
        assert!(attempt_id == 0, 0);
        
        // Get attempt details
        let attempt = money_pot_manager::test_get_attempt(attempt_id, CREATOR);
        assert!(money_pot_manager::get_attempt_id(&attempt) == 0, 1);
        assert!(money_pot_manager::get_attempt_pot_id(&attempt) == pot_id, 2);
        assert!(money_pot_manager::get_attempt_hunter(&attempt) == HUNTER, 3);
        assert!(money_pot_manager::get_attempt_is_completed(&attempt) == false, 4);
        
        // Verify pot attempt count increased
        let pot = money_pot_manager::test_get_pot(pot_id, CREATOR);
        assert!(money_pot_manager::get_pot_attempts_count(&pot) == 1, 5);
    }

    #[test]
    fun test_get_pots() {
        let creator = account::create_account_for_test(CREATOR);
        let hunter = account::create_account_for_test(HUNTER);
        let oracle = account::create_account_for_test(ORACLE);


        // Initialize the module
        money_pot_manager::test_init(&creator);

        // Create multiple pots
        let pot_id1 = money_pot_manager::test_create_pot(&creator, 1000000, 3600, 100000, HUNTER);
        let pot_id2 = money_pot_manager::test_create_pot(&creator, 2000000, 7200, 200000, HUNTER);
        
        // Get all pots
        let pots = money_pot_manager::test_get_pots(CREATOR);
        assert!(vector::length(&pots) == 2, 0);
        
        // Get active pots
        let active_pots = money_pot_manager::test_get_active_pots(CREATOR);
        assert!(vector::length(&active_pots) == 2, 1);
    }
}
