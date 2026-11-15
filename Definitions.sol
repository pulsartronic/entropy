// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @notice Represents a cryptographic hash record containing an identifier and its associated hash
 * @dev Used for tracking hash commitments across rounds
 */
struct HashRecord {
    bytes32 id;
    bytes32 hash;
}

/**
 * @notice Contains data captured when a random number is requested
 * @dev Stores entropy A and the block number at the time of the request
 */
struct EntropyRequest {
    bytes32 entropy_a;
    uint256 block_number;
}

/**
 * @notice Encapsulates the oracle's response payload for entropy generation
 * @dev Contains entropy B, entropy C, and the next hash commitment for future rounds
 */
struct EntropyResponse {
    bytes32 entropy_b;
    bytes32 entropy_c;
    bytes32 next_hash_b;
}

/**
 * @notice Result structure containing the outcome of cryptographic verification
 * @dev Includes validation flags, the final derived random number, and the next hash record
 */
struct Verified {
    bool b; // entropy_b verification
    bool c; // entropy_c verification
    bytes32 random_number;
    HashRecord next_hash_record;
}

/**
 * @title ABC Entropy Core Interface
 * @notice Interface defining the core functions of the ABC entropy and commit-reveal system
 */
interface IABCEntropy {
    /**
     * @notice Calculates the total fee required for a random number request
     * @param callback_gas_limit The gas limit allocated for the callback execution
     * @return The total fee amount denominated in wei
     */
    function get_fee(uint256 callback_gas_limit) external view returns (uint256);

    /**
     * @notice Submits a request for a random number
     * @param callback_id The unique identifier for the callback
     * @param callback_gas_limit The gas limit allocated for the callback execution
     * @param hash_record_id The identifier for the associated hash record
     * @param entropy_a Seed A provided by the requester
     * @return An EntropyRequest struct containing the recorded request details
     */
    function get(bytes32 callback_id, uint256 callback_gas_limit, bytes32 hash_record_id, bytes32 entropy_a) external payable returns (EntropyRequest memory);

    /**
     * @notice Verifies an oracle entropy response and returns the verification results
     * @param hash The expected hash commitment
     * @param request_data The original request data structure
     * @param entropy_response The response payload containing entropy B and C
     * @return A Verified struct containing the validation outcome and final random number
     */
    function verify(bytes32 hash, EntropyRequest memory request_data, EntropyResponse calldata entropy_response) external returns (Verified memory);
}

/**
 * @title Entropy Consumer Interface
 * @notice Interface that must be implemented by client dApps wanting to receive random number callbacks
 */
interface IEntropyConsumer {
    /**
     * @notice Callback function invoked by the oracle to deliver the generated entropy response
     * @param callback_id The unique identifier for the callback matching the original request
     * @param entropy_response The response payload containing the entropy values
     */
    function entropy_callback(bytes32 callback_id, EntropyResponse calldata entropy_response) external payable;
}
