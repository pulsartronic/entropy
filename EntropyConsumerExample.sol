// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct HashRecord {
	bytes32 id;
	bytes32 hash;
}

struct EntropyRequest {
	bytes32 seed;
	uint256 block_number;
}

struct UserState {
	EntropyRequest entropy_request;
	HashRecord hash_record;
}

struct EntropyResponse {
    bytes32 entropy_b;
    bytes32 entropy_c;
    bytes32 next_entropy_b;
}

struct Verified {
	bool b;
	bool c;
    bytes32 random_number;
	HashRecord next_hash_record;
}

interface IScryptEntropy {
	function get_fee(uint256 callback_gas_limit) external view returns (uint256);
	function abc_entropy(bytes32 callback_id, uint256 callback_gas_limit, bytes32 id, bytes32 seed) external payable returns (EntropyRequest memory);
	function verify(bytes32 hash, EntropyRequest calldata request_data, EntropyResponse calldata entropy_response) external returns (Verified memory);
}

contract EntropyConsumerExample {
	IScryptEntropy public scrypt_entropy;

	mapping(address => UserState) public user_state_map;

	event RandomEvent(address user, bytes32 random_number);

	constructor() {
		// Arbitrum Sepolia example address. This should change depending on the chosen network.
		scrypt_entropy = IScryptEntropy(0xd7Ca4e99F7C171B9ea2De80d3363c47009afaC5F);
	}

	// This can be called by your users.
	function get_entropy(bytes32 user_entropy) external payable {
		// This is a chance for adding user generated entropy and make "entropy_a" different for different users and dapp contracts.
		bytes memory a_seed = abi.encodePacked(user_entropy, msg.sender, address(this));
		bytes32 entropy_a = sha256(a_seed);

		// Let's say we save entropy requests by User's addresses (notice we dont check for previous requests, you should).
		UserState storage user_state = user_state_map[msg.sender];

		// And bind callbacks in the same way. Entropy response will echo this value.
		bytes32 callback_id = bytes32(uint256(uint160(msg.sender)));

		// Example limit: callback_gas_limit depends on what you do in the response function, it should be pre calculated.
		uint256 callback_gas_limit = 50000;
		// Calculates fees.
		uint256 fee = scrypt_entropy.get_fee(callback_gas_limit);

		// Request a random number. It makes the call and returns and EntropyRequest struct.
		// You could check:
		//   a) entropy_request.seed == seed
		//   b) entropy_request.block_number == some_method_to_get_it
		// You can also check its public code at http://docs.com
		user_state.entropy_request = scrypt_entropy.abc_entropy{value:fee}(callback_id, callback_gas_limit, user_state.hash_record.id, entropy_a);
	}

	// Entropy response callback.
	function entropy_callback(bytes32 callback_id, EntropyResponse calldata entropy_response) external payable {
		// Check who's calling this function, it's public.
		require(msg.sender == address(scrypt_entropy), "INVALID PROVIDER");

		// Obtain the corresponding UserState (remember this is an example).
		address user = address(uint160(uint256(callback_id)));
		UserState storage user_state = user_state_map[user];
		
		// Verify received data using our "verify" function.
		// If you want to use a different method read its public code to see what it does at http://docs.com
		Verified memory verified = scrypt_entropy.verify(user_state.hash_record.hash, user_state.entropy_request, entropy_response);
		
		if (!verified.c) {
			// this can happens if this response took more than 8190 blocks, which is unlikelly.
			// If this happens, you still have the chance to verify this operation off-chain.
			// Read the docs at http://docs.com
		}

		if (verified.b || bytes32(0) == user_state.hash_record.hash) {
			// Save next round commitment.
			user_state.hash_record = verified.next_hash_record;
			// emit obtained random number ...
			emit RandomEvent(user, verified.random_number);
		}
	}
}

