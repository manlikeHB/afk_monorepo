#[cfg(test)]
mod linear_tests {
    use afk_launchpad::launchpad::calcul::linear::{get_coin_amount, get_meme_amount};
    use afk_launchpad::types::launchpad_types::{
        TokenLaunch, BondingType, TokenQuoteBuyCoin, LiquidityType
    };
    use starknet::{ContractAddress};

    fn OWNER() -> ContractAddress {
        'owner'.try_into().unwrap()
    }
    fn CREATOR() -> ContractAddress {
        'creator'.try_into().unwrap()
    }

    const THRESHOLD_LIQUIDITY: u256 = 10;

    const SCALE_FACTOR: u256 = 100_000_000_000_000_000_000_u256;


    fn get_token_launch(
        total_supply: u256, threshold_liquidity: u256, available_supply: u256
    ) -> TokenLaunch {
        let token_quote_buy = TokenQuoteBuyCoin {
            token_address: '123'.try_into().unwrap(),
            starting_price: 0_u256,
            price: 0_u256,
            step_increase_linear: 0_u256,
            is_enable: true //TODO
        };

        let token_launch = TokenLaunch {
            owner: OWNER(),
            creator: CREATOR(),
            token_address: '123'.try_into().unwrap(),
            price: 0_u256, // Last price of the token.
            available_supply, // Available to buy
            initial_pool_supply: 0_u256, // Liquidity token to add in the DEX
            initial_available_supply: 0_u256, // Init available to buy
            total_supply, // Total supply to buy
            bonding_curve_type: BondingType::Linear,
            created_at: 0_u64,
            token_quote: token_quote_buy, // Token launched
            liquidity_raised: 0_u256, // Amount of quote raised. Need to be below threshold
            total_token_holded: 0_u256, // Number of token holded and buy
            is_liquidity_launch: true, // Liquidity launch through Ekubo or Unrug
            slope: 0_u256,
            threshold_liquidity, // Amount of maximal quote token to paid the coin launched
            liquidity_type: Option::None,
            starting_price: 0_u256,
            protocol_fee_percent: 0_u256,
            creator_fee_percent: 0_u256,
        };

        token_launch
    }

    // #[test]
    // #[should_panic(expected: ('Sellable supply == 0',))]
    // fn test_get_meme_amount_sellable_amount_zero() {
    //     let token_launch = get_token_launch(0_u256, 0_u256);
    //     let amount_in = 10;

    //     let amount = get_meme_amount(token_launch, amount_in);
    // }

    //     #[test]
    //     #[should_panic(expected: ('Threshold liquidity == 0',))]
    // fn test_get_meme_amount_threshold_liquidity_zero() {
    //     let token_launch = get_token_launch(100_000_000, THRESHOLD_LIQUIDITY);
    //     let amount_in = 10;

    //     let amount = get_meme_amount(token_launch, amount_in);
    // }

    #[test]
    fn test_get_meme_amount_with_diminishing_supply() {
        let mut available_supply = 80_000_000;
        let mut token_launch = get_token_launch(100_000_000, THRESHOLD_LIQUIDITY, available_supply);
        let amounts = array![20_000_000, 20_000_000, 20_000_000, 19_000_000];

        let mut amount_outs = array![];

        for amount_in in amounts {
            let amount_out = get_meme_amount(token_launch, amount_in);

            token_launch.available_supply -= 20_000_000;
            println!("token_launch.available_supply: {}",  token_launch.available_supply);
            amount_outs.append(amount_out);
            println!("looping ------------------------------------------",);
        };

        println!("amount 1 : {}", amount_outs.at(0));
        println!("amount 2 : {}", amount_outs.at(1));
        println!("amount 3 : {}", amount_outs.at(2));
        println!("amount 4 : {}", amount_outs.at(3));
    }

    #[test]
    fn test_get_meme_amount_fixed_supply() {
        let mut available_supply = 80_000_000;
        let mut token_launch = get_token_launch(100_000_000, THRESHOLD_LIQUIDITY, available_supply);
        let amounts = array![10_000_000, 20_000_000, 40_000_000, 60_000_000, 79_000_000];

        let mut amount_outs = array![];

        for amount_in in amounts {
            let amount_out = get_meme_amount(token_launch, amount_in);
            amount_outs.append(amount_out);

            println!("looping ------------------------------------------",);
        };

        println!("amount 1 : {}", amount_outs.at(0));
        println!("amount 2 : {}", amount_outs.at(1));
        println!("amount 3 : {}", amount_outs.at(2));
        println!("amount 4 : {}", amount_outs.at(3));
        println!("amount 4 : {}", amount_outs.at(4));
    }
}