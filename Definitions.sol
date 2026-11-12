// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct HashRecord {
	bytes32 id;
	bytes32 hash;
}

struct EntropyRequest {
	bytes32 entropy_a;
	uint256 block_number;
}

struct EntropyResponse {
    bytes32 entropy_b;
    bytes32 entropy_c;
    bytes32 next_hash_b;
}

struct Verified {
	bool b;
	bool c;
    bytes32 random_number;
	HashRecord next_hash_record;
}

interface IABCEntropy {
	function get_fee(uint256 callback_gas_limit) external view returns (uint256);
	function get(bytes32 callback_id, uint256 callback_gas_limit, bytes32 hash_record_id, bytes32 entropy_a) external payable returns (EntropyRequest memory);
	function verify(bytes32 hash, EntropyRequest memory request_data, EntropyResponse calldata entropy_response) external returns (Verified memory);
}

