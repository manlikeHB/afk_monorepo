use afk::types::launchpad_types::{
    MINTER_ROLE, ADMIN_ROLE, StoredName, BuyToken, SellToken, CreateToken, LaunchUpdated,
    TokenQuoteBuyKeys, TokenLaunch, SharesKeys, BondingType, Token, CreateLaunch
};
use starknet::ContractAddress;
use starknet::ClassHash;

#[starknet::interface]
pub trait ILaunchpadMarketplace<TContractState> {
    fn set_token(ref self: TContractState, token_quote: TokenQuoteBuyKeys);
    fn set_protocol_fee_percent(ref self: TContractState, protocol_fee_percent: u256);
    fn set_creator_fee_percent(ref self: TContractState, creator_fee_percent: u256);
    fn set_dollar_paid_coin_creation(ref self: TContractState, dollar_price: u256);
    fn set_dollar_paid_launch_creation(ref self: TContractState, dollar_price: u256);
    fn set_dollar_paid_finish_percentage(ref self: TContractState, bps: u256);
    fn set_class_hash(ref self: TContractState, class_hash: ClassHash);
    fn set_protocol_fee_destination(
        ref self: TContractState, protocol_fee_destination: ContractAddress
    );

    fn create_token(
        ref self: TContractState,
        recipient: ContractAddress,
        symbol: felt252,
        name: felt252,
        initial_supply: u256,
        contract_address_salt: felt252
    ) -> ContractAddress;

    fn create_and_launch_token(
        ref self: TContractState,
        symbol: felt252,
        name: felt252,
        initial_supply: u256,
        contract_address_salt: felt252,
    ) -> ContractAddress;
    fn launch_token(ref self: TContractState, coin_address: ContractAddress);
    fn buy_coin(ref self: TContractState, coin_address: ContractAddress, amount: u256);
    fn buy_coin_by_quote_amount(ref self: TContractState, coin_address: ContractAddress, quote_amount: u256);
    fn sell_coin(ref self: TContractState, coin_address: ContractAddress, amount: u256);
    fn get_default_token(self: @TContractState,) -> TokenQuoteBuyKeys;
    fn get_price_of_supply_key(
        self: @TContractState, coin_address: ContractAddress, amount: u256, is_decreased: bool
    ) -> u256;
    fn get_coin_amount_by_quote_amount(
        self: @TContractState, coin_address: ContractAddress, quote_amount: u256, is_decreased: bool
    ) -> u256;
    fn get_key_of_user(self: @TContractState, key_user: ContractAddress,) -> TokenLaunch;
    fn get_share_key_of_user(
        self: @TContractState, owner: ContractAddress, key_user: ContractAddress,
    ) -> SharesKeys;
    fn get_all_launch(self: @TContractState) -> Span<TokenLaunch>;
}

#[starknet::contract]
mod LaunchpadMarketplace {
    use afk::erc20::{ERC20, IERC20Dispatcher, IERC20DispatcherTrait};
    use afk::utils::{sqrt};
    use core::num::traits::Zero;
    use openzeppelin::access::accesscontrol::{AccessControlComponent};
    use openzeppelin::introspection::src5::SRC5Component;
    use starknet::syscalls::deploy_syscall;
    use starknet::{
        ContractAddress, get_caller_address, storage_access::StorageBaseAddress,
        contract_address_const, get_block_timestamp, get_contract_address, ClassHash
    };
    use super::{
        StoredName, BuyToken, SellToken, CreateToken, LaunchUpdated, SharesKeys, MINTER_ROLE,
        ADMIN_ROLE, BondingType, Token, TokenLaunch, TokenQuoteBuyKeys, CreateLaunch
    };

    const MAX_SUPPLY: u256 = 100_000_000;
    const INITIAL_SUPPLY: u256 = MAX_SUPPLY / 5;
    const MAX_STEPS_LOOP: u256 = 100;
    const LIQUIDITY_RATIO: u256 = 5;
    const PAY_TO_LAUNCH: u256 = 1;

    const MIN_FEE_PROTOCOL: u256 = 10; //0.1%
    const MAX_FEE_PROTOCOL: u256 = 1000; //10%
    const MID_FEE_PROTOCOL: u256 = 100; //1%

    const MIN_FEE_CREATOR: u256 = 100; //1%
    const MID_FEE_CREATOR: u256 = 1000; //10%
    const MAX_FEE_CREATOR: u256 = 5000; //50%

    const BPS: u256 = 10_000; // 100% = 10_000 bps

    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // AccessControl
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    // SRC5
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        coin_class_hash: ClassHash,
        quote_tokens: LegacyMap::<ContractAddress, bool>,
        quote_token: ContractAddress,
        threshold_liquidity: u256,
        threshold_market_cap: u256,
        liquidity_raised_amount_in_dollar: u256,
        names: LegacyMap::<ContractAddress, felt252>,
        token_created: LegacyMap::<ContractAddress, Token>,
        launched_coins: LegacyMap::<ContractAddress, TokenLaunch>,
        pumped_coins: LegacyMap::<ContractAddress, TokenLaunch>,
        shares_by_users: LegacyMap::<(ContractAddress, ContractAddress), SharesKeys>,
        bonding_type: LegacyMap::<ContractAddress, BondingType>,
        array_launched_coins: LegacyMap::<u64, TokenLaunch>,
        tokens_created: LegacyMap::<u64, Token>,
        launch_created: LegacyMap::<u64, TokenLaunch>,
        is_tokens_buy_enable: LegacyMap::<ContractAddress, TokenQuoteBuyKeys>,
        default_token: TokenQuoteBuyKeys,
        dollar_price_launch_pool: u256,
        dollar_price_create_token: u256,
        dollar_price_percentage: u256,
        initial_key_price: u256,
        protocol_fee_percent: u256,
        creator_fee_percent: u256,
        is_fees_protocol: bool,
        step_increase_linear: u256,
        is_custom_key_enable: bool,
        is_custom_token_enable: bool,
        protocol_fee_destination: ContractAddress,
        total_keys: u64,
        total_token: u64,
        total_launch: u64,
        total_shares_keys: u64,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        StoredName: StoredName,
        BuyToken: BuyToken,
        SellToken: SellToken,
        CreateToken: CreateToken,
        LaunchUpdated: LaunchUpdated,
        CreateLaunch: CreateLaunch,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        initial_key_price: u256,
        token_address: ContractAddress,
        step_increase_linear: u256,
        coin_class_hash: ClassHash,
        threshold_liquidity: u256,
        threshold_market_cap: u256
    ) {
        self.coin_class_hash.write(coin_class_hash);
        // AccessControl-related initialization
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(MINTER_ROLE, admin);
        self.accesscontrol._grant_role(ADMIN_ROLE, admin);

        let init_token = TokenQuoteBuyKeys {
            token_address: token_address,
            initial_key_price,
            price: initial_key_price,
            is_enable: true,
            step_increase_linear
        };
        self.is_custom_key_enable.write(false);
        self.is_custom_token_enable.write(false);
        self.default_token.write(init_token.clone());
        self.initial_key_price.write(init_token.initial_key_price);

        self.threshold_liquidity.write(threshold_liquidity);
        self.threshold_market_cap.write(threshold_market_cap);
        self.protocol_fee_destination.write(admin);
        self.step_increase_linear.write(step_increase_linear);
        self.total_keys.write(0);
        self.protocol_fee_percent.write(MID_FEE_PROTOCOL);
        self.creator_fee_percent.write(MIN_FEE_CREATOR);
    }

    // Public functions inside an impl block
    #[abi(embed_v0)]
    impl LaunchpadMarketplace of super::ILaunchpadMarketplace<ContractState> {
        // ADMIN

        fn set_token(ref self: ContractState, token_quote: TokenQuoteBuyKeys) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.is_tokens_buy_enable.write(token_quote.token_address, token_quote);
        }

        fn set_protocol_fee_percent(ref self: ContractState, protocol_fee_percent: u256) {
            assert(protocol_fee_percent < MAX_FEE_PROTOCOL, 'protocol_fee_too_high');
            assert(protocol_fee_percent > MIN_FEE_PROTOCOL, 'protocol_fee_too_low');

            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.protocol_fee_percent.write(protocol_fee_percent);
        }

        fn set_protocol_fee_destination(
            ref self: ContractState, protocol_fee_destination: ContractAddress
        ) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.protocol_fee_destination.write(protocol_fee_destination);
        }

        fn set_creator_fee_percent(ref self: ContractState, creator_fee_percent: u256) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            assert(creator_fee_percent < MAX_FEE_CREATOR, 'creator_fee_too_high');
            assert(creator_fee_percent > MIN_FEE_CREATOR, 'creator_fee_too_low');
            self.creator_fee_percent.write(creator_fee_percent);
        }

        fn set_dollar_paid_coin_creation(ref self: ContractState, dollar_price: u256) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.dollar_price_create_token.write(dollar_price);
        }

        fn set_dollar_paid_launch_creation(ref self: ContractState, dollar_price: u256) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.dollar_price_launch_pool.write(dollar_price);
        }

        fn set_dollar_paid_finish_percentage(ref self: ContractState, bps: u256) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.dollar_price_percentage.write(bps);
        }


        fn set_class_hash(ref self: ContractState, class_hash:ClassHash) {
            self.accesscontrol.assert_only_role(ADMIN_ROLE);
            self.coin_class_hash.write(class_hash);
        }

        // Create keys for an user
        fn create_token(
            ref self: ContractState,
            recipient: ContractAddress,
            symbol: felt252,
            name: felt252,
            initial_supply: u256,
            contract_address_salt: felt252
        ) -> ContractAddress {
            let caller = get_caller_address();
            let token_address = self
                ._create_token(
                    recipient, caller, symbol, name, initial_supply, contract_address_salt
                );

            token_address
        }

        // Creat coin and launch
        fn create_and_launch_token(
            ref self: ContractState,
            symbol: felt252,
            name: felt252,
            initial_supply: u256,
            contract_address_salt: felt252
        ) -> ContractAddress {
            let contract_address = get_contract_address();
            let caller = get_caller_address();
            let token_address = self
                ._create_token(
                    contract_address, caller, symbol, name, initial_supply, contract_address_salt
                );
            self._launch_token(token_address, contract_address);
            token_address
        }

        // Launch coin to pool bonding curve
        fn launch_token(ref self: ContractState, coin_address: ContractAddress) {
            let caller = get_caller_address();
            self._launch_token(coin_address, caller);
        }

        // Buy a coin to a bonding curve
        // Amount is the number of coin you want to buy
        // The function calculates the price of quote_token you need to buy the token
        fn buy_coin(ref self: ContractState, coin_address: ContractAddress, amount: u256) {
            let old_launch = self.launched_coins.read(coin_address);
            assert!(!old_launch.owner.is_zero(), "coin not found");
            let memecoin = IERC20Dispatcher { contract_address: coin_address };
            let mut pool_coin = old_launch.clone();
            let total_supply_memecoin = memecoin.total_supply();
            assert!(amount < total_supply_memecoin, "too much");
            // TODO erc20 token transfer
            let token_quote = old_launch.token_quote.clone();
            let quote_token_address = token_quote.token_address.clone();
            let protocol_fee_percent = self.protocol_fee_percent.read();
            // Update Launch pool with new values

            let mut total_price = self.get_price_of_supply_key(coin_address, amount, false);
            // println!("total_price {:?}", total_price);

            let old_price = pool_coin.price.clone();
            // println!("total price cal {:?}", total_price);
            let mut amount_protocol_fee: u256 = total_price * protocol_fee_percent / BPS;
            // println!("amount_protocol_fee cal {:?}", amount_protocol_fee);

            // let amount_creator_fee = total_price * creator_fee_percent / BPS;
            let mut remain_liquidity = total_price - amount_protocol_fee;
            // println!("remain_liquidity cal {:?}", remain_liquidity);

            // Pay with quote token
            // println!("amount_protocol_fee {:?}", amount_protocol_fee);

            let threshold_liquidity = self.threshold_liquidity.read();
           
            // Sent coin
            println!("amount transfer to buyer {:?}", amount);

            let balance_contract = memecoin.balance_of(get_contract_address());
            println!("buy amount balance_contract {:?}", balance_contract);

            let allowance = memecoin.allowance(pool_coin.owner.clone(), get_contract_address());
            println!("amount allowance {:?}", allowance);

            // TODO Fixed

            if allowance >= amount
            //  && balance_contract < amount 
            {
                println!("allowance ok {:?}", allowance);
                memecoin.transfer_from(pool_coin.owner.clone(), get_caller_address(), amount);
            }
            else if balance_contract >= amount {
                let balance_contract = memecoin.balance_of(get_contract_address());
                println!("buy amount balance_contract {:?}", balance_contract);
                // TODO FIX
                println!("transfer direct amount {:?}", amount);
                memecoin.transfer(get_caller_address(), amount);
            // memecoin.transfer_from(pool_coin.owner.clone(), get_caller_address(), amount);
            }

            let erc20 = IERC20Dispatcher { contract_address: quote_token_address };

            // TOdo fix issue price
            if total_price + old_launch.liquidity_raised.clone() > threshold_liquidity {
                // println!(
                //     "total_price + old_launch.liquidity_raised.clone() > threshold_liquidity  {:?}",
                //     total_price + old_launch.liquidity_raised.clone() > threshold_liquidity
                // );

                total_price = threshold_liquidity - old_launch.liquidity_raised.clone();
                // println!("total_price {:?}", total_price);

                amount_protocol_fee = total_price * protocol_fee_percent / BPS;
                remain_liquidity = total_price - amount_protocol_fee;

                erc20
                    .transfer_from(
                        get_caller_address(),
                        self.protocol_fee_destination.read(),
                        amount_protocol_fee
                    );
                // println!("remain_liquidity {:?}", remain_liquidity);
                erc20.transfer_from(get_caller_address(), get_contract_address(), remain_liquidity);
            } else {
                erc20
                    .transfer_from(
                        get_caller_address(),
                        self.protocol_fee_destination.read(),
                        amount_protocol_fee
                    );
                // println!("remain_liquidity {:?}", remain_liquidity);
                erc20.transfer_from(get_caller_address(), get_contract_address(), remain_liquidity);
            }


            // if balance_contract < amount {
            //     memecoin.transfer_from(pool_coin.owner.clone(), get_caller_address(), amount);
            // } else if balance_contract >= amount {
            //     let balance_contract = memecoin.balance_of(get_contract_address());
            //     println!("buy amount balance_contract {:?}", balance_contract);
            //     // TODO FIX
            //     println!("transfer direct amount {:?}", amount);
            //     memecoin.transfer(get_caller_address(), amount);
            // // memecoin.transfer_from(pool_coin.owner.clone(), get_caller_address(), amount);
            // }

            // Update share and key stats
            let mut old_share = self.shares_by_users.read((get_caller_address(), coin_address));
            // println!("old_share {:?}", old_share.owner);

            let mut share_user = old_share.clone();
            if old_share.owner.is_zero() {
                share_user =
                    SharesKeys {
                        owner: get_caller_address(),
                        key_address: coin_address,
                        amount_owned: amount,
                        amount_buy: amount,
                        amount_sell: 0,
                        created_at: get_block_timestamp(),
                        total_paid: total_price,
                    };
                let total_key_share = self.total_shares_keys.read();
                self.total_shares_keys.write(total_key_share + 1);
            } else {
                share_user.total_paid += total_price;
                share_user.amount_owned += amount;
                share_user.amount_buy += amount;
            }
            // pool_coin.price = total_price;
            // pool_coin.price = total_price / amount;
            pool_coin.liquidity_raised = pool_coin.liquidity_raised + total_price;
            // pool_coin.total_supply += amount;
            pool_coin.token_holded += amount;

            // Update state
            self.shares_by_users.write((get_caller_address(), coin_address), share_user.clone());
            self.launched_coins.write(coin_address, pool_coin.clone());

            // Check if liquidity threshold raise
            let threshold = self.threshold_liquidity.read();
            let threshold_mc = self.threshold_market_cap.read();
            // println!("threshold {:?}", threshold);
            // println!("pool_coin.liquidity_raised {:?}", pool_coin.liquidity_raised);

            let mc = (pool_coin.price * total_supply_memecoin);
            // TODO add liquidity launch
            // TOTAL_SUPPLY / 5
            // 20% go the liquidity
            // 80% bought by others
            if pool_coin.liquidity_raised >= threshold {
                // println!("mc threshold reached");
                self._add_liquidity(coin_address);
            }

            if mc >= threshold_mc {
                // println!("mc threshold reached");
                self._add_liquidity(coin_address);
            }

            self
                .emit(
                    BuyToken {
                        caller: get_caller_address(),
                        key_user: coin_address,
                        amount: amount,
                        price: total_price,
                        protocol_fee: amount_protocol_fee,
                        creator_fee: 0,
                        timestamp: get_block_timestamp(),
                        last_price: old_price,
                    }
                );
        }

        // Buy coin by quote amount
        fn buy_coin_by_quote_amount(ref self: ContractState, coin_address: ContractAddress, quote_amount: u256) {
            let old_launch = self.launched_coins.read(coin_address);
            assert!(!old_launch.owner.is_zero(), "coin not found");
            let memecoin = IERC20Dispatcher { contract_address: coin_address };
            let mut pool_coin = old_launch.clone();
            let total_supply_memecoin = memecoin.total_supply();
            assert!(quote_amount < total_supply_memecoin, "too much");
            // TODO erc20 token transfer
            let token_quote = old_launch.token_quote.clone();
            let quote_token_address = token_quote.token_address.clone();
            let erc20 = IERC20Dispatcher { contract_address: quote_token_address };
            let protocol_fee_percent = self.protocol_fee_percent.read();
            let mut amount = self._get_coin_amount_by_quote_amount(coin_address, quote_amount, false);

            let mut total_price = self.get_price_of_supply_key(coin_address, amount, false);
            // println!("total_price {:?}", total_price);

            let old_price = pool_coin.price.clone();
            // println!("total price cal {:?}", total_price);
            let mut amount_protocol_fee: u256 = total_price * protocol_fee_percent / BPS;
            // println!("amount_protocol_fee cal {:?}", amount_protocol_fee);

            // let amount_creator_fee = total_price * creator_fee_percent / BPS;
            let mut remain_liquidity = total_price - amount_protocol_fee;
            // println!("remain_liquidity cal {:?}", remain_liquidity);

            // Pay with quote token
            // println!("amount_protocol_fee {:?}", amount_protocol_fee);

            let threshold_liquidity = self.threshold_liquidity.read();

            // Transfer quote & coin

            // TOdo fix issue price
            if total_price + old_launch.liquidity_raised.clone() > threshold_liquidity {
                // println!(
                //     "total_price + old_launch.liquidity_raised.clone() > threshold_liquidity  {:?}",
                //     total_price + old_launch.liquidity_raised.clone() > threshold_liquidity
                // );

                total_price = threshold_liquidity - old_launch.liquidity_raised.clone();
                // println!("total_price {:?}", total_price);

                amount_protocol_fee = total_price * protocol_fee_percent / BPS;
                remain_liquidity = total_price - amount_protocol_fee;

                erc20
                    .transfer_from(
                        get_caller_address(),
                        self.protocol_fee_destination.read(),
                        amount_protocol_fee
                    );
                // println!("remain_liquidity {:?}", remain_liquidity);
                erc20.transfer_from(get_caller_address(), get_contract_address(), remain_liquidity);
            } else {
                erc20
                    .transfer_from(
                        get_caller_address(),
                        self.protocol_fee_destination.read(),
                        amount_protocol_fee
                    );
                // println!("remain_liquidity {:?}", remain_liquidity);
                erc20.transfer_from(get_caller_address(), get_contract_address(), remain_liquidity);
            }

            // Sent coin
            // println!("amount transfer to buyer {:?}", amount);

            let balance_contract = memecoin.balance_of(get_contract_address());
            // println!("buy amount balance_contract {:?}", balance_contract);

            let allowance = memecoin.allowance(pool_coin.owner.clone(), get_contract_address());
            // println!("amount allowance {:?}", allowance);

            // TODO Fixed

            if allowance >= amount && balance_contract < amount {
                println!("allowance ok {:?}", allowance);
                memecoin.transfer_from(pool_coin.owner.clone(), get_caller_address(), amount);
            }

            if balance_contract < amount {
                memecoin.transfer_from(pool_coin.owner.clone(), get_caller_address(), amount);
            } else if balance_contract >= amount {
                let balance_contract = memecoin.balance_of(get_contract_address());
                // println!("buy amount balance_contract {:?}", balance_contract);
                // TODO FIX
                // println!("transfer direct amount {:?}", amount);
                memecoin.transfer(get_caller_address(), amount);
            // memecoin.transfer_from(pool_coin.owner.clone(), get_caller_address(), amount);
            }

            // Update share and key stats
            let mut old_share = self.shares_by_users.read((get_caller_address(), coin_address));
            // println!("old_share {:?}", old_share.owner);

            let mut share_user = old_share.clone();
            if old_share.owner.is_zero() {
                share_user =
                    SharesKeys {
                        owner: get_caller_address(),
                        key_address: coin_address,
                        amount_owned: amount,
                        amount_buy: amount,
                        amount_sell: 0,
                        created_at: get_block_timestamp(),
                        total_paid: total_price,
                    };
                let total_key_share = self.total_shares_keys.read();
                self.total_shares_keys.write(total_key_share + 1);
            } else {
                share_user.total_paid += total_price;
                share_user.amount_owned += amount;
                share_user.amount_buy += amount;
            }
            // pool_coin.price = total_price;
            // pool_coin.price = total_price / amount;
            pool_coin.liquidity_raised = pool_coin.liquidity_raised + total_price;
            // pool_coin.total_supply += amount;
            pool_coin.token_holded += amount;

            // Update state
            self.shares_by_users.write((get_caller_address(), coin_address), share_user.clone());
            self.launched_coins.write(coin_address, pool_coin.clone());

            // Check if liquidity threshold raise
            let threshold = self.threshold_liquidity.read();
            let threshold_mc = self.threshold_market_cap.read();
            // println!("threshold {:?}", threshold);
            // println!("pool_coin.liquidity_raised {:?}", pool_coin.liquidity_raised);

            let mc = (pool_coin.price * total_supply_memecoin);
            // TODO add liquidity launch
            // TOTAL_SUPPLY / 5
            // 20% go the liquidity
            // 80% bought by others
            if pool_coin.liquidity_raised >= threshold {
                // println!("mc threshold reached");
                self._add_liquidity(coin_address);
            }

            if mc >= threshold_mc {
                // println!("mc threshold reached");
                self._add_liquidity(coin_address);
            }

            self
                .emit(
                    BuyToken {
                        caller: get_caller_address(),
                        key_user: coin_address,
                        amount: amount,
                        price: total_price,
                        protocol_fee: amount_protocol_fee,
                        creator_fee: 0,
                        timestamp: get_block_timestamp(),
                        last_price: old_price,
                    }
                );
        }

        fn sell_coin(ref self: ContractState, coin_address: ContractAddress, amount: u256) {
            let old_pool = self.launched_coins.read(coin_address);
            assert(!old_pool.owner.is_zero(), 'coin not found');

            // let caller = get_caller_address();
            let mut old_share = self.shares_by_users.read((get_caller_address(), coin_address));

            let mut share_user = old_share.clone();
            // Verify Amount owned
            assert!(old_share.amount_owned >= amount, "share too low");
            assert!(old_pool.total_supply >= amount, "above supply");

            // TODO erc20 token transfer
            let token = old_pool.token_quote.clone();
            let total_supply = old_pool.total_supply;
            let token_quote = old_pool.token_quote.clone();
            let quote_token_address = token_quote.token_address.clone();

            let erc20 = IERC20Dispatcher { contract_address: quote_token_address };
            let protocol_fee_percent = self.protocol_fee_percent.read();
            let creator_fee_percent = self.creator_fee_percent.read();

            assert!(total_supply >= amount, "share > supply");
            let old_price = old_pool.price.clone();

            // Update keys with new values
            let mut pool_update = TokenLaunch {
                owner: old_pool.owner,
                token_address: old_pool.token_address, // CREATE 404
                created_at: old_pool.created_at,
                token_quote: token_quote,
                initial_key_price: token_quote.initial_key_price,
                bonding_curve_type: old_pool.bonding_curve_type,
                total_supply: old_pool.total_supply,
                available_supply: old_pool.available_supply,
                price: old_pool.price,
                liquidity_raised: old_pool.liquidity_raised,
                token_holded: old_pool.token_holded,
                is_liquidity_launch: old_pool.is_liquidity_launch,
                slope:old_pool.slope,
            };

            let mut total_price = self.get_price_of_supply_key(coin_address, amount, true);
            // total_price -= pool_update.initial_key_price.clone();

            let amount_protocol_fee: u256 = total_price * protocol_fee_percent / BPS;
            let amount_creator_fee = total_price * creator_fee_percent / BPS;
            // let remain_liquidity = total_price - amount_creator_fee - amount_protocol_fee;
            let remain_liquidity = total_price - amount_protocol_fee;

            if old_share.owner.is_zero() {
                share_user =
                    SharesKeys {
                        owner: get_caller_address(),
                        key_address: coin_address,
                        amount_owned: amount,
                        amount_buy: amount,
                        amount_sell: amount,
                        created_at: get_block_timestamp(),
                        total_paid: total_price,
                    };
            } else {
                share_user.total_paid += total_price;
                share_user.amount_owned -= amount;
                share_user.amount_sell += amount;
            }
            // pool_update.price = total_price;
            // key.total_supply -= amount;
            pool_update.total_supply = pool_update.total_supply - amount;
            pool_update.liquidity_raised = pool_update.liquidity_raised + remain_liquidity;
            self
                .shares_by_users
                .write((get_caller_address(), coin_address.clone()), share_user.clone());
            self.launched_coins.write(coin_address.clone(), pool_update.clone());

            // Transfer to Liquidity, Creator and Protocol
            // println!("contract_balance {}", contract_balance);
            // println!("transfer creator fee {}", amount_creator_fee.clone());
            // println!("transfer liquidity {}", remain_liquidity.clone());
            erc20.transfer(get_caller_address(), remain_liquidity);
            // println!("transfer protocol fee {}", amount_protocol_fee.clone());
            // erc20.transfer(self.protocol_fee_destination.read(), amount_protocol_fee);

            self
                .emit(
                    SellToken {
                        caller: get_caller_address(),
                        key_user: coin_address,
                        amount: amount,
                        price: total_price,
                        protocol_fee: amount_protocol_fee,
                        creator_fee: amount_creator_fee,
                        timestamp: get_block_timestamp(),
                        last_price: old_price,
                    }
                );
        }

        fn get_default_token(self: @ContractState) -> TokenQuoteBuyKeys {
            self.default_token.read()
        }
        // The function calculates the amiunt of quote_token you need to buy a coin in the pool
        fn get_price_of_supply_key(
            self: @ContractState, coin_address: ContractAddress, amount: u256, is_decreased: bool
        ) -> u256 {
            self._get_price_of_supply_key(coin_address, amount, is_decreased)
        }

        fn get_coin_amount_by_quote_amount(
            self: @ContractState, coin_address: ContractAddress, quote_amount: u256, is_decreased: bool
        ) -> u256 {
            self._get_coin_amount_by_quote_amount(coin_address, quote_amount, is_decreased)
        }

        fn get_key_of_user(self: @ContractState, key_user: ContractAddress,) -> TokenLaunch {
            self.launched_coins.read(key_user)
        }

        fn get_share_key_of_user(
            self: @ContractState, owner: ContractAddress, key_user: ContractAddress,
        ) -> SharesKeys {
            self.shares_by_users.read((owner, key_user))
        }

        fn get_all_launch(self: @ContractState) -> Span<TokenLaunch> {
            let max_key_id = self.total_keys.read() + 1;
            let mut keys: Array<TokenLaunch> = ArrayTrait::new();
            let mut i = 0; //Since the stream id starts from 0
            loop {
                if i >= max_key_id {}
                let key = self.array_launched_coins.read(i);
                if key.owner.is_zero() {
                    break keys.span();
                }
                keys.append(key);
                i += 1;
            }
        }
    }

    // // Could be a group of functions about a same topic
    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _create_token(
            ref self: ContractState,
            recipient: ContractAddress,
            owner: ContractAddress,
            symbol: felt252,
            name: felt252,
            initial_supply: u256,
            contract_address_salt: felt252
        ) -> ContractAddress {
            let mut calldata = array![name.into(), symbol.into()];
            Serde::serialize(@initial_supply, ref calldata);
            Serde::serialize(@recipient, ref calldata);
            Serde::serialize(@18, ref calldata);

            let (token_address, _) = deploy_syscall(
                self.coin_class_hash.read(), contract_address_salt, calldata.span(), false
            )
                .unwrap();
            // .unwrap_syscall();
            // println!("token address {:?}", token_address);

            let token = Token {
                token_address: token_address,
                owner: owner,
                name,
                symbol,
                total_supply: initial_supply,
                initial_supply: initial_supply,
                created_at: get_block_timestamp(),
                token_type: Option::None,
            };

            self.token_created.write(token_address, token);

            self
                .emit(
                    CreateToken {
                        caller: get_caller_address(),
                        token_address: token_address,
                        total_supply: initial_supply.clone(),
                        initial_supply
                    }
                );
            token_address
        }


        fn _launch_token(
            ref self: ContractState, coin_address: ContractAddress, caller: ContractAddress
        ) {
            // let caller = get_caller_address();
            let token = self.token_created.read(coin_address);
            assert!(!token.owner.is_zero(), "not launch");
            let mut token_to_use = self.default_token.read();
            let mut quote_token_address = token_to_use.token_address.clone();

            let bond_type = BondingType::Linear;
            // let erc20 = IERC20Dispatcher { contract_address: quote_token_address };
            let memecoin = IERC20Dispatcher { contract_address: coin_address };
            let total_supply = memecoin.total_supply();

            let threshold = self.threshold_liquidity.read();

            // TODO calculate initial key price based on
            // MC
            // Threshold liquidity
            // total supply

            // let (slope, ini_price) = self._calculate_pricing(total_supply/LIQUIDITY_RATIO);
            let (slope, ini_price) = self._calculate_pricing(total_supply-(total_supply/LIQUIDITY_RATIO));
            // println!("slope key price {:?}",slope);
            // println!("ini_price key price {:?}",ini_price);

            // let initial_key_price = ini_price;
            let initial_key_price = threshold / total_supply;
            
            // println!("initial key price {:?}",initial_key_price);
            // // @TODO Deploy an ERC404
            // // Option for liquidity providing and Trading
            let launch_token_pump = TokenLaunch {
                owner: caller,
                token_address: caller, // CREATE 404
                total_supply: total_supply,
                available_supply: total_supply,
                // Todo price by pricetype after fix Enum instantiate
                bonding_curve_type: Option::Some(bond_type),
                // bonding_curve_type: BondingType,
                created_at: get_block_timestamp(),
                token_quote: token_to_use.clone(),
                initial_key_price: initial_key_price.clone(),
                // initial_key_price: token_to_use.initial_key_price,
                price: 0,
                liquidity_raised: 0,
                token_holded: 0,
                is_liquidity_launch: false,
                slope:slope
            // token_holded:1
            };

            // Send supply need to launch your coin
            let amount_needed = total_supply.clone();
            // println!("amount_needed {:?}", amount_needed);

            let allowance = memecoin.allowance(caller, get_contract_address());
            // println!("test allowance contract {:?}", allowance);

            let balance_contract = memecoin.balance_of(get_contract_address());
            // println!("amount balance_contract {:?}", balance_contract);

            // println!("caller {:?}", caller);

            // Check if allowance or balance is ok

            if balance_contract < total_supply {
                if allowance >= amount_needed {
                    // println!("allowance > amount_needed{:?}", allowance > amount_needed);
                    memecoin
                        .transfer_from(
                            caller, get_contract_address(), total_supply - balance_contract
                        );
                } else {
                    panic!("no supply provided")
                }
            }

            // memecoin.transfer_from(get_caller_address(), get_contract_address(), amount_needed);
            self.launched_coins.write(coin_address, launch_token_pump.clone());

            self
                .emit(
                    CreateLaunch {
                        caller: get_caller_address(),
                        token_address: quote_token_address,
                        amount: 1,
                        price: 1,
                    }
                );
        }

        // TODO add liquidity to Ekubo, Jediswap and others exchanges enabled
        fn _add_liquidity(ref self: ContractState, coin_address: ContractAddress) {}

        // Function to calculate the price for the next token to be minted
        fn _get_linear_price(self: @ContractState, initial_price: u256, slope: u256, supply: u256) -> u256 {
            return initial_price + (slope * supply);
        }

        fn _get_coin_amount_by_quote_amount(
            self: @ContractState, coin_address: ContractAddress, quote_amount: u256, is_decreased: bool

        ) -> u256  {

            let pool_coin= self.launched_coins.read(coin_address);

            let mut coin_amount=0;
            let slope= pool_coin.slope;
            let mut a = slope/2;
            let initial_price=pool_coin.initial_key_price.clone();
            let mut current_supply=pool_coin.token_holded.clone();

            let sold_supply=current_supply.clone();
            let mut b=initial_price+slope* sold_supply-slope/2;
            // let c = -quote_amount;
            let c = quote_amount;


            // Solving the quadratic equation: ax^2 + bx + c = 0
            // x = (-b ± sqrt(b^2 - 4ac)) / 2a

            // TODO how do negative number

            let discriminant=(b*b) + (4*a*c);
            assert!(discriminant > 0, "no real root");
            let sqrt_discriminant= sqrt(discriminant);

            // TODO B need to be negative

            let n1= (b + sqrt_discriminant) / (2*a);
            let n2= (b - sqrt_discriminant) / (2*a);

            // let n1= (-b + sqrt_discriminant) / (2*a);
            // let n2= (-b - sqrt_discriminant) / (2*a);


            if n1 > n2 {
                n1
            } else {
                n1
            }


            // let total_supply=pool_coin.total_supply.clone();

            // let mut current_price= self._get_linear_price(pool_coin.initial_key_price, pool_coin.slope, current_supply);

            // let mut amount= quote_amount.clone();

            // println!("amount {:?}",amount);
            // println!("current_price {:?}",amount);
            // println!("total_supply {:?}",total_supply);
            // println!("slope {:?}",slope);
            // println!("current_supply {:?}",current_supply);

            // while amount >= current_price && current_supply < total_supply / LIQUIDITY_RATIO {

            //     amount-=current_price;
            //     coin_amount+=1;
            //     current_supply+=1;
            //     current_price= self._get_linear_price(pool_coin.initial_key_price, pool_coin.slope, current_supply);
            // };


            // coin_amount
            
        }

        // fn _get_coin_amount_by_quote_amount(
        //     self: @ContractState, coin_address: ContractAddress, quote_amount: u256, is_decreased: bool

        // ) -> u256  {


        //     let mut coin_amount=0;
        //     let pool_coin= self.launched_coins.read(coin_address);


        //     let mut current_supply=pool_coin.token_holded.clone();
        //     let total_supply=pool_coin.total_supply.clone();

        //     let mut current_price= self._get_linear_price(pool_coin.initial_key_price, pool_coin.slope, current_supply);

        //     let mut amount= quote_amount.clone();

        //     println!("amount {:?}",amount);
        //     println!("current_price {:?}",amount);
        //     println!("total_supply {:?}",total_supply);
        //     println!("slope {:?}",slope);
        //     println!("current_supply {:?}",current_supply);

        //     while amount >= current_price && current_supply < total_supply / LIQUIDITY_RATIO {

        //         amount-=current_price;
        //         coin_amount+=1;
        //         current_supply+=1;
        //         current_price= self._get_linear_price(pool_coin.initial_key_price, pool_coin.slope, current_supply);
        //     };


        //     coin_amount
            
        // }

        fn _calculate_pricing(ref self: ContractState, liquidity_available:u256)  -> (u256, u256) {

            let threshold_liquidity = self.threshold_liquidity.read();
            let slope= (2 *threshold_liquidity ) / (liquidity_available * (liquidity_available-1));
            // println!("slope {:?}", slope);

            let initial_price= (2* threshold_liquidity / liquidity_available) - slope *  (liquidity_available -1) / 2;
            // println!("initial_price {:?}", initial_price);
            (slope, initial_price)
        }

      

        fn _get_price_of_supply_key(
            self: @ContractState, coin_address: ContractAddress, amount: u256, is_decreased: bool
        ) -> u256 {
            let pool = self.launched_coins.read(coin_address);
            let mut total_supply = pool.token_holded.clone();
            let mut final_supply = total_supply + amount;

            if is_decreased {
                final_supply = total_supply - amount;
            }

            let mut actual_supply = total_supply;
            let mut initial_key_price = pool.initial_key_price.clone();
            let step_increase_linear =pool.slope.clone();
            let bonding_type = pool.bonding_curve_type.clone();
            match bonding_type {
                Option::Some(x) => {
                    match x {
                        BondingType::Linear => {
                            // println!("Linear curve {:?}", x);
                            if !is_decreased {
                                // println!("initial_key_price {:?}", initial_key_price);
                                // println!("step_increase_linear {:?}", step_increase_linear);
                                // println!("final_supply {:?}", final_supply);
                             

                                let start_price = initial_key_price
                                    + (step_increase_linear * actual_supply);
                                // println!("start_price {:?}", start_price);
                             
                                let end_price = initial_key_price
                                    + (step_increase_linear * final_supply);
                                // let end_price = initial_key_price
                                // + (step_increase_linear * final_supply -1);
                                // println!("end_price{:?}", end_price);

                                // let total_price = amount * (start_price + end_price) / 2;
                                let total_price = (final_supply - actual_supply)
                                    * (start_price + end_price)
                                    / 2;
                                total_price
                            } else {
                                // println!("initial_key_price {:?}", initial_key_price);
                                // println!("step_increase_linear {:?}", step_increase_linear);
                                // println!("final_supply {:?}", final_supply);

                                let start_price = initial_key_price
                                    + (step_increase_linear * final_supply);
                                // println!("start_price {:?}", start_price);
                                let end_price = initial_key_price
                                    + (step_increase_linear * actual_supply);
                                // println!("end_price{:?}", end_price);

                                // let total_price = amount * (start_price + end_price) / 2;
                                let total_price = (actual_supply - final_supply)
                                    * (start_price + end_price)
                                    / 2;

                                // println!("total_price {}", total_price.clone());
                                total_price
                            }
                        },
                        _ => {
                            let start_price = initial_key_price
                                + (step_increase_linear * actual_supply);
                            let end_price = initial_key_price
                                + (step_increase_linear * final_supply);
                            let total_price = amount * (start_price + end_price) / 2;
                            total_price
                        },
                    }
                },
                Option::None => {
                    let start_price = initial_key_price + (step_increase_linear * actual_supply);
                    let end_price = initial_key_price + (step_increase_linear * final_supply);
                    let total_price = amount * (start_price + end_price) / 2;
                    total_price
                }
            }
        }
    }
}
