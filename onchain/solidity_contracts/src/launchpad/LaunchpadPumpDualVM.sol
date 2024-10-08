// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {CairoLib} from "kakarot-lib/CairoLib.sol";

using CairoLib for uint256;

contract LaunchpadPumpDualVM {
    /// @dev The address of the cairo contract to call
    uint256 immutable starknetLaunchpad;

    /// @dev The address of the kakarot starknet contract to call
    uint256 immutable kakarot;

    /// @dev The cairo function selector to call - `create_token`
    uint256 constant FUNCTION_SELECTOR_CREATE_TOKEN = uint256(keccak256("create_token")) % 2 ** 250;

   /// @dev The cairo function selector to call - `create_and_launch_token`
    uint256 constant FUNCTION_SELECTOR_CREATE_TOKEN_AND_LAUNCH= uint256(keccak256("create_and_launch_token")) % 2 ** 250;


    /// @dev The cairo function selector to call - `launch_token`
    uint256 constant FUNCTION_SELECTOR_LAUNCH_TOKEN = uint256(keccak256("launch_token")) % 2 ** 250;


    /// @dev The cairo function selector to call - `get_coin_launch`
    uint256 constant FUNCTION_SELECTOR_GET_LAUNCH = uint256(keccak256("get_coin_launch")) % 2 ** 250;

   /// @dev The cairo function selector to call - `buy_coin_by_quote_amount`
    uint256 constant FUNCTION_SELECTOR_BUY_COIN = uint256(keccak256("buy_coin_by_quote_amount")) % 2 ** 250;

   /// @dev The cairo function selector to call - `sell_coin`
    uint256 constant FUNCTION_SELECTOR_SELL_COIN = uint256(keccak256("sell_coin")) % 2 ** 250;

    struct SharesTokenUser {
     address owner;
        address token_address;
        uint256 price;
        uint256 amount_owned;
        uint256 amount_buy;
        uint256 amount_sell;
        uint256 total_paid;
        uint64 created_at;
    }

    struct TokenLaunch {
        address owner;
        address token_address;
        uint256 price;
        uint256 available_supply;
        uint256 total_supply;
        uint256 initial_key_price;
        uint256 liquidity_raised;
        uint256 token_holded;
        bool is_liquidity_launch;
        uint256 slop;
        uint64 created_at;
    }

    struct Token {
        address owner;
        address token_address;
        bytes symbol;
        bytes name;
        uint256 total_supply;
        uint256 initial_supply;
        uint64 created_at;
        
    }

    constructor(
        uint256 _kakarot,
        uint256 _starknetLaunchpad) {
        kakarot = _kakarot;
        starknetLaunchpad = _starknetLaunchpad;
    }

    function getLaunchPump(uint256 tokenAddress) public {

        uint256[] memory tokenAddressCalldata = new uint256[](1);
        tokenAddressCalldata[0] = uint256(uint160(tokenAddress));
        uint256 tokenStarknetAddress =
            abi.decode(starknetLaunchpad.staticcallCairo("compute_starknet_address", tokenAddressCalldata), (uint256));

        // call launch that sent struct
        // todo how do it?
    }


   function bytesToUint256(bytes calldata b) internal pure returns (uint256) {
        require(b.length <= 32, "Byte array should be no longer than 32 bytes");
        return abi.decode(abi.encodePacked(new bytes(32 - b.length), b), (uint256));
    }

    function bytesFeltToUint256(bytes calldata b) internal pure returns (uint256) {
        require(b.length <= 31, "Byte array should be no longer than 31 bytes");
        return abi.decode(abi.encodePacked(new bytes(32 - b.length), b), (uint256));
    }


    /** */
    function createToken(address recipient,
      bytes calldata symbol,
      bytes calldata name,
      uint256 initialSupply,
      bytes calldata contractAddressSalt
    ) public {

        uint256[] memory recipientAddressCalldata = new uint256[](1);
        recipientAddressCalldata[0] = uint256(uint160(recipient));

        uint256 recipientStarknetAddress =
            abi.decode(kakarot.staticcallCairo("compute_starknet_address", recipientAddressCalldata), (uint256));

        uint128 amountLow = uint128(initialSupply);
        uint128 amountHigh = uint128(initialSupply >> 128);
        // Decode the first 32 bytes (a uint256 is 32 bytes)
        uint256 symbolAsUint = bytesFeltToUint256(symbol);
        uint256 nameAsUint = bytesFeltToUint256(name);
        uint256 contractAddressSaltResult = bytesFeltToUint256(contractAddressSalt);

        // uint256 symbolAsUint = convertBytesToUint256(symbol);
        // uint256 nameAsUint = convertBytesToUint256(name);
        // uint256 contractAddressSaltResult = convertBytesToUint256(contractAddressSalt);

        uint256[] memory createTokenCallData = new uint256[](6);
        createTokenCallData[0] = recipientStarknetAddress;
        createTokenCallData[1] = uint(symbolAsUint);
        createTokenCallData[2] = uint(nameAsUint);
        createTokenCallData[3] = uint256(amountLow);
        createTokenCallData[4] = uint256(amountHigh);
        createTokenCallData[5] = uint256(contractAddressSaltResult);

        // TODO change to create token only
        starknetLaunchpad.callCairo(FUNCTION_SELECTOR_CREATE_TOKEN, createTokenCallData);
        // starknetLaunchpad.callCairo(FUNCTION_SELECTOR_CREATE_TOKEN_AND_LAUNCH, createTokenCallData);

        // starknetLaunchpad.callCairo("create_token", createTokenCallData);
        // starknetLaunchpad.staticcallCairo("create_token", createTokenCallData);

    }

    function createAndLaunchToken(
         bytes calldata symbol,
         bytes calldata name,
         uint256 initialSupply,
         bytes calldata contractAddressSalt
        ) public {
            uint128 amountLow = uint128(initialSupply);
            uint128 amountHigh = uint128(initialSupply >> 128);

            uint256[] memory createLaunchTokenCallData = new uint256[](5);
            // Decode the first 32 bytes (a uint256 is 32 bytes)
            uint256 symbolAsUint = bytesFeltToUint256(symbol);
            uint256 nameAsUint = bytesFeltToUint256(name);
            uint256 contractAddressSaltResult = bytesFeltToUint256(contractAddressSalt);
            createLaunchTokenCallData[0] = uint(symbolAsUint);
            createLaunchTokenCallData[1] = uint(nameAsUint);
            createLaunchTokenCallData[2] = uint256(amountLow);
            createLaunchTokenCallData[3] = uint256(amountHigh);
            createLaunchTokenCallData[4] = uint256(contractAddressSaltResult);

            starknetLaunchpad.callCairo(FUNCTION_SELECTOR_CREATE_TOKEN_AND_LAUNCH, createLaunchTokenCallData);
            // starknetLaunchpad.staticcallCairo("create_and_launch_token", createLaunchTokenCallData);


    }

    // Launch a token already deployed
    // Need to be approve or transfer to the launchpad
    function launchToken(
        address coinAddress
    )  public {

        uint256[] memory coinAddressCalldata = new uint256[](1);
        coinAddressCalldata[0] = uint256(uint160(coinAddress));
        uint256 coinStarknetAddress =
            abi.decode(kakarot.staticcallCairo("compute_starknet_address", coinAddressCalldata), (uint256));

        uint256[] memory launchTokenCalldata = new uint256[](1);
        launchTokenCalldata[0] = coinStarknetAddress;

        starknetLaunchpad.callCairo(FUNCTION_SELECTOR_LAUNCH_TOKEN, launchTokenCalldata);
        
    }

    function buyToken(
        address coinAddress
    ) public {
         uint256[] memory coinAddressCalldata = new uint256[](1);
        coinAddressCalldata[0] = uint256(uint160(coinAddress));
        uint256 coinStarknetAddress =
            abi.decode(kakarot.staticcallCairo("compute_starknet_address", coinAddressCalldata), (uint256));

        uint256[] memory buyTokenCalldata = new uint256[](1);
        buyTokenCalldata[0] = coinStarknetAddress;
        starknetLaunchpad.callCairo(FUNCTION_SELECTOR_BUY_COIN, buyTokenCalldata);

    }

    function sellToken(
        address coinAddress
    ) public {
        uint256[] memory coinAddressCalldata = new uint256[](1);
        coinAddressCalldata[0] = uint256(uint160(coinAddress));
        uint256 coinStarknetAddress =
            abi.decode(kakarot.staticcallCairo("compute_starknet_address", coinAddressCalldata), (uint256));

        uint256[] memory sellTokenCalldata = new uint256[](1);
        sellTokenCalldata[0] = coinStarknetAddress;
        starknetLaunchpad.callCairo(FUNCTION_SELECTOR_SELL_COIN, sellTokenCalldata);

    }

    // Function to cast `bytes` to `bytes31`
    function bytesToBytes31(bytes memory b) internal pure returns (bytes31) {
        require(b.length == 31, "Invalid bytes length for bytes31");

        bytes31 result;
        assembly {
            result := mload(add(b, 31))
        }

        return result;
    }

    // Function to convert `bytes31` to `uint256`
    function bytes31ToUint256(bytes31 input) internal pure returns (uint256) {
        uint256 result;
        assembly {
            result := mload(add(input, 31)) // Read 31 bytes as uint256
        }
        return result;
    }

    // Function to convert `bytes calldata` to `bytes31` and then to uint256
    function convertBytesToUint256(bytes calldata input) internal pure returns (uint256) {
        require(input.length == 31, "Input must be exactly 31 bytes long");

        // Convert `bytes calldata` to `bytes31`
        bytes31 fixedBytes = bytes31(bytesToBytes31(input));

        // Convert `bytes31` to `uint256`
        uint256 result = bytes31ToUint256(fixedBytes);

        return result;
    }
    
}