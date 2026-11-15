// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Shared definitions, structs and interfaces.
import "@pulsartronic/entropy/Definitions.sol";

/**
 * @notice Data structure representing the response payload returned by the oracle
 * @dev Encapsulates the target application address, callback identifier, 
 *      allocated gas limit, and the cryptographic entropy response.
 */
struct ResponseData {
	address app;
    bytes32 callback_id;
    uint256 callback_gas_limit;
	EntropyResponse entropy_response;
}

/**
 * @title Arbitrum System Precompile Interface
 * @notice Interface for interacting with the ArbSys precompile on Arbitrum chains to obtain true L2 block numbers
 * @dev Reference: https://docs.arbitrum.io/arbitrum-essentials/precompiles/reference#arbsys
 *      Note: This interface is specific to Arbitrum and is not present on standard Ethereum L1 or non-Arbitrum networks.
 */
interface ArbSys {
    /**
     * @notice Retrieves the current L2 block number on Arbitrum
     * @return The current block number as a uint256
     */
    function arbBlockNumber() external view returns (uint256);
}

/**
 * @title A simple random number generator for EVM chains
 * @author mrvifas
 * @notice Allows contracts to obtain a fair and verifiable random number
 * @dev Implements a commit-reveal scheme utilizing a three-seed mechanism (A, B, and C)
 */
contract ABCEntropy is IABCEntropy {
    /**
     * @notice The address of the designated operator with administrative privileges
     */
    address public operator;

    /**
     * @notice The flat fee amount charged for operations, denominated in wei
     */
    uint256 public fee;

    /**
     * @notice The currently configured gas price parameter
     */
	uint256 public gas_price;

    /**
     * @notice Reference to the Arbitrum ArbSys precompile contract
     * @dev Interacts with address 0x64 to retrieve the true L2 block number 
     *      rather than the standard L1 block estimation provided by block.number.
     *      Note: This is exclusively used on Arbitrum chains and is ignored or unused on other networks.
     */
	ArbSys arb_sys = ArbSys(0x0000000000000000000000000000000000000064);

    /**
     * @notice Address of the EIP-2935 historical block hash system contract
     * @dev Provides access to on-chain block hashes, serving as seed C in the commit-reveal scheme.
     *      Specification: https://eips.ethereum.org/EIPS/eip-2935
     */
	address constant HISTORY = 0x0000F90827F1C53a10cb7A02335B175320002935;

    /**
     * @notice Emitted when a contract requests a random number
     * @dev Monitored by the off-chain oracle to trigger fulfillment
     * @param app The address of the requesting application contract
     * @param callback_id The unique identifier for the callback
     * @param gas_limit The gas limit allocated for the callback execution
     * @param hash_record_id The identifier for the associated hash record
     */
    event RequestEvent(address app, bytes32 callback_id, uint256 gas_limit, bytes32 hash_record_id);

    /**
     * @notice Emitted when a callback execution fails or runs out of gas
     * @dev dApps should monitor this event to handle execution errors appropriately
     * @param app The address of the application associated with the callback
     * @param callback_id The unique identifier of the failed callback
     */
    event CallbackFailedEvent(address indexed app, bytes32 indexed callback_id);

    /**
     * @notice Initializes the contract, setting the deployer as the operator and configuring initial fee and gas price parameters
     * @dev Assigns msg.sender to the operator state variable and initializes core configuration values
     * @param initial_fee The initial fee amount required for contract operations
     * @param initial_gas_price The initial gas price configuration value
     */
	constructor(uint256 initial_fee, uint256 initial_gas_price) {
        operator = msg.sender;
        fee = initial_fee;
        gas_price = initial_gas_price;
	}

	/**
     * @notice Restricts function execution to the designated operator
     * @dev Reverts with "INVALID_CALLER" if the message sender is not the authorized operator
     */
	modifier only_operator() {
		require(msg.sender == operator, "INVALID_CALLER");
		_;
	}

    /**
     * @notice Updates the designated operator address
     * @dev Restricted to the current operator via the only_operator modifier
     * @param new_operator The address of the new operator
     */
    function set_operator(address new_operator) external only_operator {
        operator = new_operator;
    }

    /**
     * @notice Withdraws the entire contract balance to a specified recipient
     * @dev Reverts if the contract balance is zero or if the low-level transfer fails
     * @param recipient The address to receive the withdrawn funds
     */
	function withdraw(address recipient) external only_operator {
		uint256 balance = address(this).balance;
		require(balance > 0, "NO_FUNDS_TO_WITHDRAW");
		(bool success, ) = payable(recipient).call{value: balance}("");
		require(success, "TRANSFER_FAILED");
	}

    /**
     * @notice Sets a new flat fee for operations
     * @param new_fee The new flat fee amount denominated in wei
     */
	function set_fee(uint256 new_fee) external payable only_operator {
		fee = new_fee;
	}
	
    /**
     * @notice Sets a new gas price parameter
     * @param new_gas_price The new gas price value to configure
     */
	function set_gas_price(uint256 new_gas_price) external payable only_operator {
		gas_price = new_gas_price;
	}
	
    /**
     * @notice Calculates the total fee based on a provided gas limit
     * @dev Computes: fee + (gas_limit * gas_price)
     * @param gas_limit The gas limit allocated for the operation
     * @return gass_fee The total calculated fee amount
     */
	function get_fee(uint256 gas_limit) external view returns (uint256 gass_fee) {
		return fee + gas_limit * gas_price;
	}

    /**
     * @notice Requests a random number using a commit-reveal scheme
     * @dev Calculates the required fee, validates msg.value, records seed A and the current block number, and emits a request event for the oracle
     * @param callback_id The unique identifier for the callback
     * @param gas_limit The gas limit allocated for the callback execution
     * @param hash_record_id The identifier for the associated hash record
     * @param entropy_a Seed A provided by the caller for the commit-reveal scheme
     * @return request_data The populated EntropyRequest struct containing the recorded request details
     */
    function get(bytes32 callback_id, uint256 gas_limit, bytes32 hash_record_id, bytes32 entropy_a) external payable returns (EntropyRequest memory request_data) {
        // Calculate the total required fee based on the gas limit and pricing parameters
        uint256 total_fee = fee + gas_limit * gas_price;
        
        // Ensure the attached ETH value meets the required fee
        require(msg.value >= total_fee, "INSUFFICIENT_FEE");
        
        // Store seed A in the request structure
        request_data.entropy_a = entropy_a;
        
        // Capture the current L2 block number via the Arbitrum precompile for future hash retrieval
        // request_data.block_number = arb_sys.arbBlockNumber(); // Alternative block number fallback if deployed on Arbitrum networks
        request_data.block_number = block.number;

        // Emit the request event for off-chain oracle listeners
        emit RequestEvent(msg.sender, callback_id, gas_limit, hash_record_id);
    }

    /**
     * @notice Submits oracle responses and executes callbacks for pending requests
     * @dev Iterates through a batch of response data, invoking the target application's 
     *      callback via low-level call with a custom gas limit. Emits CallbackFailedEvent 
     *      if a callback execution fails. Restricted to the authorized operator.
     * @param response_data_set An array of ResponseData structs containing callback targets, limits, and entropy payloads
     */
    function response(ResponseData[] calldata response_data_set) external payable only_operator {
        // Iterate through each response item in the provided batch
        for (uint256 index = 0; index < response_data_set.length; index++) {
            ResponseData calldata response_data = response_data_set[index];
            
            // Execute the low-level call to the consumer app with the allocated callback gas limit
            (bool success, ) = response_data.app.call{gas: response_data.callback_gas_limit}(
                abi.encodeWithSelector(IEntropyConsumer.entropy_callback.selector, response_data.callback_id, response_data.entropy_response)
            );
            
            // If the callback execution fails or runs out of gas, emit an error event rather than reverting the entire batch
            if (!success) {
                emit CallbackFailedEvent(response_data.app, response_data.callback_id);
            }
        }
    }

    /**
     * @notice Verifies the oracle's entropy response against commitments and derives the final random number
     * @dev Validates entropy B and C. Regarding the validation flags in the returned `Verified` struct:
     *      - If **b** and **c** are both true, the verification business logic executed successfully.
     *      - **b** will be false when the original hash identifier was zero. e.g., the first time an external contract makes a call. Don't use this number, make a new call.
     *      - **c** may evaluate to false if the oracle's response takes more than 8,191 blocks, which is unlikely. Read this https://still.defining/docs
     * @param hash The expected hash commitment to verify against
     * @param entropy_request The original request structure containing seed A and the recorded block number
     * @param entropy_response The response payload containing entropy B, entropy C, and the next round's hash commitment
     * @return verified The populated Verified struct containing validation flags (b, c), the final random number, and the next hash record
     */
    function verify(bytes32 hash, EntropyRequest memory entropy_request, EntropyResponse calldata entropy_response) external view returns (Verified memory verified) {
        // Extract entropy B from the response payload
        bytes32 entropy_b = entropy_response.entropy_b;
        // Verify that the hash of entropy B matches the expected commitment
        verified.b = hash == keccak256(bytes.concat(entropy_b));
        
        // Entropy C
        bytes32 entropy_c = entropy_response.entropy_c; // fallback value.
        // Obtains the hash of the block in which the initial request was generated.
        (bool success, bytes memory data) = HISTORY.staticcall(abi.encode(entropy_request.block_number));
        if (verified.c = (success && data.length == 32)) {
            entropy_c = abi.decode(data, (bytes32));
        }
        
        // Combine entropy A entropy B and C to derive the final pseudorandom number
        bytes memory abc_seed = bytes.concat(entropy_request.entropy_a, entropy_b, entropy_c);
        verified.random_number = keccak256(abc_seed);
        
        // Construct and return the commitment record required for a future round
        verified.next_hash_record.id = entropy_b;
        verified.next_hash_record.hash = entropy_response.next_hash_b;
    }
}

