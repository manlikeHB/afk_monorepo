#[starknet::contract]
pub mod NFTMintQuest {
    use afk_games::interfaces::nfts::{ICanvasNFTStoreDispatcher, ICanvasNFTStoreDispatcherTrait};
    use afk_games::interfaces::quests::IQuest;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map
    };

    use starknet::{ContractAddress, get_caller_address};
    #[storage]
    struct Storage {
        canvas_nft: ContractAddress,
        art_peace: ContractAddress,
        reward: u32,
        is_daily: bool,
        day_index: u32,
        claimed: Map<ContractAddress, bool>,
    }

    #[derive(Drop, Serde)]
    pub struct NFTMintQuestInitParams {
        pub canvas_nft: ContractAddress,
        pub art_peace: ContractAddress,
        pub reward: u32,
        pub is_daily: bool,
        pub day_index: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState, init_params: NFTMintQuestInitParams) {
        self.canvas_nft.write(init_params.canvas_nft);
        self.art_peace.write(init_params.art_peace);
        self.reward.write(init_params.reward);
        self.is_daily.write(init_params.is_daily);
        self.day_index.write(init_params.day_index);
    }

    #[abi(embed_v0)]
    impl NFTMintQuestImpl of IQuest<ContractState> {
        fn get_reward(self: @ContractState) -> u32 {
            self.reward.read()
        }

        fn is_claimable(
            self: @ContractState, user: ContractAddress, calldata: Span<felt252>
        ) -> bool {
            if self.claimed.read(user) {
                return false;
            }

            let token_id_felt = *calldata.at(0);
            let token_id: u256 = token_id_felt.into();

            let nft_store = ICanvasNFTStoreDispatcher { contract_address: self.canvas_nft.read() };
            let token_minter = nft_store.get_nft_minter(token_id);

            if token_minter != user {
                return false;
            }

            if self.is_daily.read() {
                let day_index = nft_store.get_nft_day_index(token_id);
                if day_index != self.day_index.read() {
                    return false;
                }
            }

            return true;
        }

        fn claim(ref self: ContractState, user: ContractAddress, calldata: Span<felt252>) -> u32 {
            assert(get_caller_address() == self.art_peace.read(), 'Only ArtPeace can claim quests');

            assert(self.is_claimable(user, calldata), 'Quest not claimable');

            self.claimed.entry(user).write(true);
            let reward = self.reward.read();

            reward
        }
    }
}
