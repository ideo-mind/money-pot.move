// money_pot_manager.move
module money_pot::money_pot_manager {
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use aptos_std::simple_map::{Self, SimpleMap, create, borrow, borrow_mut};
    use std::signer;
    use std::vector;
    use std::option;

    const DIFFICULTY_MOD: u64 = 11;
    const HUNTER_SHARE_PERCENT: u64 = 40;

    struct MoneyPot has key, store, copy, drop {
        id: u64,
        creator: address,
        total_amount: u64,
        fee: u64,
        created_at: u64,
        expires_at: u64,
        is_active: bool,
        attempts_count: u64,
        one_fa_address: address,
        token_metadata: address,  // Store the token type being used
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
        signer_cap: SignerCapability,
        resource_address: address,  // Store the resource account address
    }

    struct PotEvent has drop, store {
        id: u64,
        event_type: vector<u8>,
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

    fun clamp(value: u64, min: u64, max: u64): u64 {
        if (value < min) {
            min
        } else if (value > max) {
            max
        } else {
            value
        }
    }

    fun init_module(deployer: &signer) {
        let (resource_signer, signer_cap) = account::create_resource_account(deployer, b"money_pot");
        let resource_address = signer::address_of(&resource_signer);
        
        move_to(&resource_signer, Registry {
            next_pot_id: 0,
            pots: create<u64, MoneyPot>(),
            next_attempt_id: 0,
            attempts: create<u64, Attempt>(),
            events: account::new_event_handle<PotEvent>(&resource_signer),
            signer_cap,
            resource_address,
        });
    }

    #[test_only]
    public fun test_init(deployer: &signer) {
        let signer_cap = account::create_test_signer_cap(signer::address_of(deployer));
        move_to(deployer, Registry {
            next_pot_id: 0,
            pots: create<u64, MoneyPot>(),
            next_attempt_id: 0,
            attempts: create<u64, Attempt>(),
            events: account::new_event_handle<PotEvent>(deployer),
            signer_cap,
            resource_address: signer::address_of(deployer),
        });
    }

    #[test_only]
    public fun test_create_pot(
        creator: &signer,
        amount: u64,
        duration_seconds: u64,
        fee: u64,
        one_fa_address: address,
        token_metadata: address
    ): u64 acquires Registry {
        assert!(fee <= amount, E_INVALID_FEE);

        let registry = borrow_global_mut<Registry>(signer::address_of(creator));
        let id = registry.next_pot_id;
        registry.next_pot_id = id + 1;

        let now = 0;
        let pot = MoneyPot {
            id,
            creator: signer::address_of(creator),
            total_amount: amount,
            fee,
            created_at: now,
            expires_at: now + duration_seconds,
            is_active: true,
            attempts_count: 0,
            one_fa_address,
            token_metadata,
        };

        simple_map::add(&mut registry.pots, id, pot);
        id
    }

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

        let attempt_id = registry.next_attempt_id;
        registry.next_attempt_id = attempt_id + 1;

        let now = 0;
        let difficulty = clamp((pot.attempts_count % DIFFICULTY_MOD) + 2, 1, pot.attempts_count + 2);

        let attempt = Attempt {
            id: attempt_id,
            pot_id,
            hunter: signer::address_of(hunter),
            expires_at: now + 300,
            difficulty,
            is_completed: false,
        };

        simple_map::add(&mut registry.attempts, attempt_id, attempt);
        attempt_id
    }

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

    // Create pot with any fungible asset
    public fun create_pot(
        creator: &signer,
        token_metadata_address: address,  // The fungible asset metadata object address
        amount: u64,
        duration_seconds: u64,
        fee: u64,
        one_fa_address: address
    ): u64 acquires Registry {
        assert!(fee <= amount, E_INVALID_FEE);

        let registry = borrow_global_mut<Registry>(@money_pot);
        let resource_addr = registry.resource_address;
        let id = registry.next_pot_id;
        registry.next_pot_id = id + 1;

        let now = timestamp::now_seconds();
        let pot = MoneyPot {
            id,
            creator: signer::address_of(creator),
            total_amount: amount,
            fee,
            created_at: now,
            expires_at: now + duration_seconds,
            is_active: true,
            attempts_count: 0,
            one_fa_address,
            token_metadata: token_metadata_address,
        };

        simple_map::add(&mut registry.pots, id, pot);

        // Transfer fungible asset to contract
        let metadata = object::address_to_object<Metadata>(token_metadata_address);
        primary_fungible_store::transfer(creator, metadata, resource_addr, amount);

        event::emit_event(
            &mut registry.events,
            PotEvent {
                id,
                event_type: b"created",
                timestamp: now,
                actor: signer::address_of(creator),
            }
        );

        id
    }

    public entry fun create_pot_entry(
        creator: &signer,
        token_metadata_address: address,
        amount: u64,
        duration_seconds: u64,
        fee: u64,
        one_fa_address: address
    ) acquires Registry {
        create_pot(creator, token_metadata_address, amount, duration_seconds, fee, one_fa_address);
    }

    #[view]
    public fun get_balance(account: address, token_metadata_address: address): u64 {
        let metadata = object::address_to_object<Metadata>(token_metadata_address);
        primary_fungible_store::balance(account, metadata)
    }

    public fun attempt_pot(
        hunter: &signer,
        pot_id: u64
    ): u64 acquires Registry {
        let registry = borrow_global_mut<Registry>(@money_pot);
        let resource_addr = registry.resource_address;
        let pot = borrow_mut(&mut registry.pots, &pot_id);

        assert!(pot.is_active, E_POT_NOT_ACTIVE);
        assert!(timestamp::now_seconds() < pot.expires_at, E_POT_EXPIRED);
        assert!(signer::address_of(hunter) != pot.creator, E_CREATOR_CANNOT_ATTEMPT);

        let entry_fee = pot.fee;
        let metadata = object::address_to_object<Metadata>(pot.token_metadata);
        
        assert!(
            primary_fungible_store::balance(signer::address_of(hunter), metadata) >= entry_fee,
            E_INSUFFICIENT_FUNDS
        );

        // Transfer fee to contract
        primary_fungible_store::transfer(hunter, metadata, resource_addr, entry_fee);
        pot.total_amount = pot.total_amount + entry_fee;
        pot.attempts_count = pot.attempts_count + 1;

        let attempt_id = registry.next_attempt_id;
        registry.next_attempt_id = attempt_id + 1;

        let now = timestamp::now_seconds();
        let difficulty = clamp((pot.attempts_count % DIFFICULTY_MOD) + 2, 1, pot.attempts_count + 2);

        let attempt = Attempt {
            id: attempt_id,
            pot_id,
            hunter: signer::address_of(hunter),
            expires_at: now + 300,
            difficulty,
            is_completed: false,
        };

        simple_map::add(&mut registry.attempts, attempt_id, attempt);

        event::emit_event(
            &mut registry.events,
            PotEvent {
                id: attempt_id,
                event_type: b"attempted",
                timestamp: now,
                actor: signer::address_of(hunter),
            }
        );

        attempt_id
    }

    public entry fun attempt_pot_entry(
        hunter: &signer,
        pot_id: u64
    ) acquires Registry {
        attempt_pot(hunter, pot_id);
    }

    public entry fun attempt_completed(
        oracle: &signer,
        attempt_id: u64,
        status: bool
    ) acquires Registry {
        assert!(signer::address_of(oracle) == @trusted_oracle, E_UNAUTHORIZED);

        let registry = borrow_global_mut<Registry>(@money_pot);
        let contract_signer = account::create_signer_with_capability(&registry.signer_cap);
        
        let attempt = borrow_mut(&mut registry.attempts, &attempt_id);
        let pot_id = attempt.pot_id;
        let pot = borrow_mut(&mut registry.pots, &pot_id);

        assert!(pot.is_active, E_POT_NOT_ACTIVE);
        assert!(timestamp::now_seconds() < pot.expires_at, E_POT_EXPIRED);
        assert!(timestamp::now_seconds() < attempt.expires_at, E_ATTEMPT_EXPIRED);
        assert!(!attempt.is_completed, E_ATTEMPT_COMPLETED);

        attempt.is_completed = true;

        let now = timestamp::now_seconds();
        let metadata = object::address_to_object<Metadata>(pot.token_metadata);

        if (status) {
            pot.is_active = false;

            let hunter_share = pot.total_amount * HUNTER_SHARE_PERCENT / 100;
            let platform_share = pot.total_amount - hunter_share;

            // Transfer from contract to hunter and platform
            primary_fungible_store::transfer(&contract_signer, metadata, attempt.hunter, hunter_share);
            primary_fungible_store::transfer(&contract_signer, metadata, @platform, platform_share);

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

    public entry fun expire_pot(
        caller: &signer,
        pot_id: u64
    ) acquires Registry {
        let registry = borrow_global_mut<Registry>(@money_pot);
        let contract_signer = account::create_signer_with_capability(&registry.signer_cap);
        
        let pot = borrow_mut(&mut registry.pots, &pot_id);

        assert!(pot.is_active, E_POT_NOT_ACTIVE);
        assert!(timestamp::now_seconds() >= pot.expires_at, E_NOT_EXPIRED);
        assert!(signer::address_of(caller) == pot.creator, E_UNAUTHORIZED);

        pot.is_active = false;

        let metadata = object::address_to_object<Metadata>(pot.token_metadata);
        primary_fungible_store::transfer(&contract_signer, metadata, pot.creator, pot.total_amount);

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

    #[view]
    public fun get_pots(): vector<u64> acquires Registry {
        let registry = borrow_global<Registry>(@money_pot);
        simple_map::keys(&registry.pots)
    }

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

    #[view]
    public fun get_pot(pot_id: u64): MoneyPot acquires Registry {
        let registry = borrow_global<Registry>(@money_pot);
        *borrow(&registry.pots, &pot_id)
    }

    #[view]
    public fun get_attempt(attempt_id: u64): Attempt acquires Registry {
        let registry = borrow_global<Registry>(@money_pot);
        *borrow(&registry.attempts, &attempt_id)
    }

    #[test_only]
    public fun get_pot_id(pot: &MoneyPot): u64 { pot.id }
    #[test_only]
    public fun get_pot_creator(pot: &MoneyPot): address { pot.creator }
    #[test_only]
    public fun get_pot_total_amount(pot: &MoneyPot): u64 { pot.total_amount }
    #[test_only]
    public fun get_pot_fee(pot: &MoneyPot): u64 { pot.fee }
    #[test_only]
    public fun get_pot_is_active(pot: &MoneyPot): bool { pot.is_active }
    #[test_only]
    public fun get_pot_attempts_count(pot: &MoneyPot): u64 { pot.attempts_count }
    #[test_only]
    public fun get_attempt_id(attempt: &Attempt): u64 { attempt.id }
    #[test_only]
    public fun get_attempt_pot_id(attempt: &Attempt): u64 { attempt.pot_id }
    #[test_only]
    public fun get_attempt_hunter(attempt: &Attempt): address { attempt.hunter }
    #[test_only]
    public fun get_attempt_is_completed(attempt: &Attempt): bool { attempt.is_completed }
}
