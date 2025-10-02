// money_pot_manager.move
module money_pot::money_pot_manager {
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::simple_map::{Self, SimpleMap, create, borrow, borrow_mut};
    use std::signer;
    use std::vector;

    // Using APT as the coin type for now (you can change this to USDC later)
    use aptos_framework::aptos_coin::AptosCoin;

    const DIFFICULTY_MOD: u64 = 11;
    const HUNTER_SHARE_PERCENT: u64 = 40;

    struct MoneyPot has key, store, copy, drop {
        id: u64,
        creator: address,
        total_apt: u64,
        fee: u64,  // Fixed entry fee per attempt
        created_at: u64,
        expires_at: u64,
        is_active: bool,
        attempts_count: u64,
        one_fa_address: address,  // 1FA Aptos address as unique pot identifier
    }

    struct Attempt has key, store, copy, drop {
        id: u64,
        pot_id: u64,
        hunter: address,
        expires_at: u64,
        difficulty: u64,
        is_completed: bool,
    }

    struct Registry has key {
        next_pot_id: u64,
        pots: SimpleMap<u64, MoneyPot>,
        next_attempt_id: u64,
        attempts: SimpleMap<u64, Attempt>,
        events: event::EventHandle<PotEvent>,
    }

    struct PotEvent has drop, store {
        id: u64,  // pot_id or attempt_id
        event_type: vector<u8>,  // "created", "attempted", "solved", "expired"
        timestamp: u64,
        actor: address,
    }

    // Errors
    const E_INVALID_FEE: u64 = 0;
    const E_POT_NOT_ACTIVE: u64 = 1;
    const E_CREATOR_CANNOT_ATTEMPT: u64 = 2;
    const E_INSUFFICIENT_FUNDS: u64 = 3;
    const E_POT_EXPIRED: u64 = 4;
    const E_NOT_EXPIRED: u64 = 5;
    const E_ATTEMPT_EXPIRED: u64 = 6;
    const E_ATTEMPT_COMPLETED: u64 = 7;
    const E_UNAUTHORIZED: u64 = 8;

    // Helper function to clamp a value between min and max
    fun clamp(value: u64, min: u64, max: u64): u64 {
        if (value < min) {
            min
        } else if (value > max) {
            max
        } else {
            value
        }
    }

    // Initialize module
    fun init_module(deployer: &signer) {
        move_to(deployer, Registry {
            next_pot_id: 0,
            pots: create<u64, MoneyPot>(),
            next_attempt_id: 0,
            attempts: create<u64, Attempt>(),
            events: account::new_event_handle<PotEvent>(deployer),
        });
    }

    // Test initialization function
    #[test_only]
    public fun test_init(deployer: &signer) {
        // For testing, create Registry at the deployer's address
        move_to(deployer, Registry {
            next_pot_id: 0,
            pots: create<u64, MoneyPot>(),
            next_attempt_id: 0,
            attempts: create<u64, Attempt>(),
            events: account::new_event_handle<PotEvent>(deployer),
        });
    }

    // Test-specific create_pot function that works with test setup
    #[test_only]
    public fun test_create_pot(
        creator: &signer,
        amount: u64,
        duration_seconds: u64,
        fee: u64,
        one_fa_address: address
    ): u64 acquires Registry {
        assert!(fee <= amount, E_INVALID_FEE);

        let registry = borrow_global_mut<Registry>(signer::address_of(creator));
        let id = registry.next_pot_id;
        registry.next_pot_id = id + 1;

        let now = 0; // Use 0 for testing
        let pot = MoneyPot {
            id,
            creator: signer::address_of(creator),
            total_apt: amount,
            fee,
            created_at: now,
            expires_at: now + duration_seconds,
            is_active: true,
            attempts_count: 0,
            one_fa_address,
        };

        simple_map::add(&mut registry.pots, id, pot);
        id
    }

    // Test-specific attempt_pot function
    #[test_only]
    public fun test_attempt_pot(
        hunter: &signer,
        pot_id: u64,
        creator_addr: address
    ): u64 acquires Registry {
        let registry = borrow_global_mut<Registry>(creator_addr);
        let pot = borrow_mut(&mut registry.pots, &pot_id);

        assert!(pot.is_active, E_POT_NOT_ACTIVE);
        assert!(signer::address_of(hunter) != pot.creator, E_CREATOR_CANNOT_ATTEMPT);

        pot.attempts_count = pot.attempts_count + 1;

        // Create attempt
        let attempt_id = registry.next_attempt_id;
        registry.next_attempt_id = attempt_id + 1;

        let now = 0; // Use 0 for testing
        let difficulty = clamp((pot.attempts_count % DIFFICULTY_MOD) + 2, 1, pot.attempts_count + 2);

        let attempt = Attempt {
            id: attempt_id,
            pot_id,
            hunter: signer::address_of(hunter),
            expires_at: now + 300,  // 5 minutes
            difficulty,
            is_completed: false,
        };

        simple_map::add(&mut registry.attempts, attempt_id, attempt);
        attempt_id
    }

    // Test-specific getter functions
    #[test_only]
    public fun test_get_pot(pot_id: u64, creator_addr: address): MoneyPot acquires Registry {
        let registry = borrow_global<Registry>(creator_addr);
        *borrow(&registry.pots, &pot_id)
    }

    #[test_only]
    public fun test_get_attempt(attempt_id: u64, creator_addr: address): Attempt acquires Registry {
        let registry = borrow_global<Registry>(creator_addr);
        *borrow(&registry.attempts, &attempt_id)
    }

    #[test_only]
    public fun test_get_pots(creator_addr: address): vector<u64> acquires Registry {
        let registry = borrow_global<Registry>(creator_addr);
        simple_map::keys(&registry.pots)
    }

    #[test_only]
    public fun test_get_active_pots(creator_addr: address): vector<u64> acquires Registry {
        let registry = borrow_global<Registry>(creator_addr);
        let keys = simple_map::keys(&registry.pots);
        let active = vector::empty<u64>();
        let i = 0;
        while (i < vector::length(&keys)) {
            let id = *vector::borrow(&keys, i);
            let pot = borrow(&registry.pots, &id);
            if (pot.is_active) {
                vector::push_back(&mut active, id);
            };
            i = i + 1;
        };
        active
    }

    // Create pot, return pot_id
    public fun create_pot(
        creator: &signer,
        amount: u64,
        duration_seconds: u64,
        fee: u64,
        one_fa_address: address
    ): u64 acquires Registry {
        assert!(fee <= amount, E_INVALID_FEE);

        let registry = borrow_global_mut<Registry>(@money_pot);
        let id = registry.next_pot_id;
        registry.next_pot_id = id + 1;

        let now = timestamp::now_seconds();
        let pot = MoneyPot {
            id,
            creator: signer::address_of(creator),
            total_apt: amount,
            fee,
            created_at: now,
            expires_at: now + duration_seconds,
            is_active: true,
            attempts_count: 0,
            one_fa_address,
        };

        simple_map::add(&mut registry.pots, id, pot);

        // Escrow APT
        coin::transfer<AptosCoin>(creator, @money_pot, amount);

        // Event
        event::emit_event(
            &mut registry.events,
            PotEvent {
                id,
                event_type: b"created",
                timestamp: now,
                actor: signer::address_of(creator),
            }
        );

        id  // Return pot_id
    }

    // Entry wrapper for create_pot
    public entry fun create_pot_entry(
        creator: &signer,
        amount: u64,
        duration_seconds: u64,
        fee: u64,
        one_fa_address: address
    ) acquires Registry {
        create_pot(creator, amount, duration_seconds, fee, one_fa_address);
    }

    // Attempt pot, return attempt_id
    public fun attempt_pot(
        hunter: &signer,
        pot_id: u64
    ): u64 acquires Registry {
        let registry = borrow_global_mut<Registry>(@money_pot);
        let pot = borrow_mut(&mut registry.pots, &pot_id);

        assert!(pot.is_active, E_POT_NOT_ACTIVE);
        assert!(timestamp::now_seconds() < pot.expires_at, E_POT_EXPIRED);
        assert!(signer::address_of(hunter) != pot.creator, E_CREATOR_CANNOT_ATTEMPT);

        let entry_fee = pot.fee;
        assert!(coin::balance<AptosCoin>(signer::address_of(hunter)) >= entry_fee, E_INSUFFICIENT_FUNDS);

        // Transfer fee to escrow, add to pot total
        coin::transfer<AptosCoin>(hunter, @money_pot, entry_fee);
        pot.total_apt = pot.total_apt + entry_fee;

        pot.attempts_count = pot.attempts_count + 1;

        // Create attempt
        let attempt_id = registry.next_attempt_id;
        registry.next_attempt_id = attempt_id + 1;

        let now = timestamp::now_seconds();
        let difficulty = clamp((pot.attempts_count % DIFFICULTY_MOD) + 2, 1, pot.attempts_count + 2);

        let attempt = Attempt {
            id: attempt_id,
            pot_id,
            hunter: signer::address_of(hunter),
            expires_at: now + 300,  // 5 minutes
            difficulty,
            is_completed: false,
        };

        simple_map::add(&mut registry.attempts, attempt_id, attempt);

        // Event for attempt
        event::emit_event(
            &mut registry.events,
            PotEvent {
                id: attempt_id,
                event_type: b"attempted",
                timestamp: now,
                actor: signer::address_of(hunter),
            }
        );

        attempt_id  // Return attempt_id
    }

    // Entry wrapper for attempt_pot
    public entry fun attempt_pot_entry(
        hunter: &signer,
        pot_id: u64
    ) acquires Registry {
        attempt_pot(hunter, pot_id);
    }

    // Mark attempt completed (success/failed) by oracle
    public entry fun attempt_completed(
        oracle: &signer,
        attempt_id: u64,
        status: bool  // true = success, false = failed
    ) acquires Registry {
        assert!(signer::address_of(oracle) == @trusted_oracle, E_UNAUTHORIZED);

        let registry = borrow_global_mut<Registry>(@money_pot);
        let attempt = borrow_mut(&mut registry.attempts, &attempt_id);
        let pot_id = attempt.pot_id;
        let pot = borrow_mut(&mut registry.pots, &pot_id);

        assert!(pot.is_active, E_POT_NOT_ACTIVE);
        assert!(timestamp::now_seconds() < pot.expires_at, E_POT_EXPIRED);
        assert!(timestamp::now_seconds() < attempt.expires_at, E_ATTEMPT_EXPIRED);
        assert!(!attempt.is_completed, E_ATTEMPT_COMPLETED);

        attempt.is_completed = true;

        let now = timestamp::now_seconds();

        if (status) {
            // Success: deactivate pot, payout 40% to hunter, rest to platform
            pot.is_active = false;

            let hunter_share = pot.total_apt * HUNTER_SHARE_PERCENT / 100;
            let platform_share = pot.total_apt - hunter_share;

            coin::transfer<AptosCoin>(@money_pot, attempt.hunter, hunter_share);
            coin::transfer<AptosCoin>(@money_pot, @platform, platform_share);

            event::emit_event(
                &mut registry.events,
                PotEvent {
                    id: pot_id,
                    event_type: b"solved",
                    timestamp: now,
                    actor: attempt.hunter,
                }
            );
        } else {
            // Failed: mark completed, no payout
            event::emit_event(
                &mut registry.events,
                PotEvent {
                    id: attempt_id,
                    event_type: b"failed",
                    timestamp: now,
                    actor: attempt.hunter,
                }
            );
        }
    }

    // Expire pot
    public entry fun expire_pot(
        caller: &signer,
        pot_id: u64
    ) acquires Registry {
        let registry = borrow_global_mut<Registry>(@money_pot);
        let pot = borrow_mut(&mut registry.pots, &pot_id);

        assert!(pot.is_active, E_POT_NOT_ACTIVE);
        assert!(timestamp::now_seconds() >= pot.expires_at, E_NOT_EXPIRED);
        assert!(signer::address_of(caller) == pot.creator, E_UNAUTHORIZED);

        pot.is_active = false;

        // Return to creator
        coin::transfer<AptosCoin>(@money_pot, pot.creator, pot.total_apt);

        // Event
        event::emit_event(
            &mut registry.events,
            PotEvent {
                id: pot_id,
                event_type: b"expired",
                timestamp: timestamp::now_seconds(),
                actor: pot.creator,
            }
        );
    }

    // Getter for all pot_ids
    #[view]
    public fun get_pots(): vector<u64> acquires Registry {
        let registry = borrow_global<Registry>(@money_pot);
        simple_map::keys(&registry.pots)
    }

    // Getter for active pot_ids
    #[view]
    public fun get_active_pots(): vector<u64> acquires Registry {
        let registry = borrow_global<Registry>(@money_pot);
        let keys = simple_map::keys(&registry.pots);
        let active = vector::empty<u64>();
        let i = 0;
        while (i < vector::length(&keys)) {
            let id = *vector::borrow(&keys, i);
            let pot = borrow(&registry.pots, &id);
            if (pot.is_active) {
                vector::push_back(&mut active, id);
            };
            i = i + 1;
        };
        active
    }

    // Getter for pot by id
    #[view]
    public fun get_pot(pot_id: u64): MoneyPot acquires Registry {
        let registry = borrow_global<Registry>(@money_pot);
        *borrow(&registry.pots, &pot_id)
    }

    // Getter for attempt by id
    #[view]
    public fun get_attempt(attempt_id: u64): Attempt acquires Registry {
        let registry = borrow_global<Registry>(@money_pot);
        *borrow(&registry.attempts, &attempt_id)
    }

    // Getter functions for MoneyPot fields
    #[test_only]
    public fun get_pot_id(pot: &MoneyPot): u64 {
        pot.id
    }

    #[test_only]
    public fun get_pot_creator(pot: &MoneyPot): address {
        pot.creator
    }

    #[test_only]
    public fun get_pot_total_apt(pot: &MoneyPot): u64 {
        pot.total_apt
    }

    #[test_only]
    public fun get_pot_fee(pot: &MoneyPot): u64 {
        pot.fee
    }

    #[test_only]
    public fun get_pot_is_active(pot: &MoneyPot): bool {
        pot.is_active
    }

    #[test_only]
    public fun get_pot_attempts_count(pot: &MoneyPot): u64 {
        pot.attempts_count
    }

    // Getter functions for Attempt fields
    #[test_only]
    public fun get_attempt_id(attempt: &Attempt): u64 {
        attempt.id
    }

    #[test_only]
    public fun get_attempt_pot_id(attempt: &Attempt): u64 {
        attempt.pot_id
    }

    #[test_only]
    public fun get_attempt_hunter(attempt: &Attempt): address {
        attempt.hunter
    }

    #[test_only]
    public fun get_attempt_is_completed(attempt: &Attempt): bool {
        attempt.is_completed
    }
}