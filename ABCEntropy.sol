// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Shared definitions, structs and interfaces.
import "./Definitions.sol";

// Data structure the Oracle responds with.
struct ResponseData {
	address app;
    bytes32 callback_id;
    uint256 callback_gas_limit;
	EntropyResponse entropy_response;
}

// In Arbitrun we need a especial contract to obtain block numbers. 
// https://docs.arbitrum.io/arbitrum-essentials/precompiles/reference#arbsys
interface ArbSys {
    function arbBlockNumber() external view returns (uint256);
}

/**
 * This contract is in charge of comunicating with the Oracle to make requests and process responses.
 */
contract ABCEntropy is IABCEntropy {
    // 
    address public immutable owner;

    // Flat fee (wei)
    uint256 public fee;
    // Current gas price
	uint256 public gas_price;

    // Create Arbitrum's block number handler.
	ArbSys arb_sys = ArbSys(0x0000000000000000000000000000000000000064);

    // This will give us on-chain block hashes which is the the C in ABC.
    // https://eips.ethereum.org/EIPS/eip-2935
	address constant HISTORY = 0x0000F90827F1C53a10cb7A02335B175320002935;

    // Emitted when a contract requests a random number. This is what the Oracle is listening to.
    event RequestEvent(address app, bytes32 callback_id, uint256 gas_limit, bytes32 hash_record_id);

    // Emitted if a callback run out of gas or something went wrong during the callback execution.
    // dApps should be listening to this event in order to know about the error.
    event CallbackFailedEvent(address indexed app, bytes32 indexed callback_id);

    // Contract's constructor, set initial fee and gas price.
	constructor(uint256 initial_fee, uint256 initial_gas_price) {
        owner = msg.sender;
        fee = initial_fee;
        gas_price = initial_gas_price;
	}

	// Modifiers
	modifier only_owner() {
		require(msg.sender == owner, "INVALID_CALLER");
		_;
	}

    // 
	function withdraw(address recipient) external only_owner {
		uint256 balance = address(this).balance;
		require(balance > 0, "NO_FUNDS_TO_WITHDRAWN");
		(bool success, ) = payable(recipient).call{value: balance}("");
		require(success, "TRANSFER_FAILED");
	}

    // Sets a new flat fee (wei)
	function set_fee(uint256 new_fee) external payable only_owner {
		fee = new_fee;
	}
	
    // Sets a new gas price
	function set_gas_price(uint256 new_gas_price) external payable only_owner {
		gas_price = new_gas_price;
	}
	
    // Calculates fees based on provided gas limit.
	function get_fee(uint256 gas_limit) external view returns (uint256 gass_fee) {
		return fee + gas_limit * gas_price;
	}

    // This is the function external contract will call to get random numbers.
    function get(bytes32 callback_id, uint256 gas_limit, bytes32 hash_record_id, bytes32 entropy_a) external payable returns (EntropyRequest memory request_data) {
        uint256 total_fee = fee + gas_limit * gas_price;
		require(msg.value >= total_fee, "INSUFFICIENT_FEE");
        
        request_data.entropy_a = entropy_a;
        request_data.block_number = arb_sys.arbBlockNumber();
        //request_data.block_number = block.number;

        emit RequestEvent(msg.sender, callback_id, gas_limit, hash_record_id);
    }

    // 
    function response(ResponseData[] calldata response_data_set) external payable only_owner {
		for (uint256 index = 0; index < response_data_set.length; index++) {
			ResponseData calldata response_data = response_data_set[index];
			(bool success, ) = response_data.app.call{gas: response_data.callback_gas_limit}(
				abi.encodeWithSelector(IEntropyConsumer.entropy_callback.selector, response_data.callback_id, response_data.entropy_response)
			);
            if (!success) {
                emit CallbackFailedEvent(response_data.app, response_data.callback_id);
            }
		}
	}

    // 
    function verify(bytes32 hash, EntropyRequest memory entropy_request, EntropyResponse calldata entropy_response) external view returns (Verified memory verified) {
        // ENTROPY B
        bytes32 entropy_b = entropy_response.entropy_b;
        verified.b = hash == keccak256(bytes.concat(entropy_b));
        
        // ENTROPY C
        bytes32 entropy_c = entropy_response.entropy_c; // fallback value.
        (bool success, bytes memory data) = HISTORY.staticcall(abi.encode(entropy_request.block_number));
        if (verified.c = (success && data.length == 32)) {
            entropy_c = abi.decode(data, (bytes32)); // externally obtained target value.
        }
        
        // ABC ENTROPY
        bytes memory abc_seed = bytes.concat(entropy_request.entropy_a, entropy_b, entropy_c);
        verified.random_number = keccak256(abc_seed);
        
        // RETURN COMMITMENT FOR A FUTURE ROUND
        verified.next_hash_record.id = entropy_b;
        verified.next_hash_record.hash = entropy_response.next_hash_b;
    }
}

