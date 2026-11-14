# ABC Entropy

**Randomness your contract can prove.**

This simple system delivers verifiable random numbers to your dapp, checkable on-chain.

---

## Table of contents

- [How ABC entropy works](#how-abc-entropy-works)
- [Getting started](#getting-started-consuming-entropy-from-a-contract)
- [Features](#features)
- [Supported networks](#supported-networks)
- [Security model](#security-model)

## How ABC entropy works

This is a commit-reveal scheme built on three components, each contributing part of the final random number:

| | Component | Role |
|---|---|---|
| **A** | Your dapp users | Your frontend provides the user's entropy contribution. |
| **B** | Generator (us) | We lock our entropy contribution behind a hash beforehand, allowing post-reveal verification. |
| **C** | Sequencer (the network) | It introduces additional entropy so that no party, including us, can manipulate the outcome. |

As long as we aren't running the sequencer, the system remains tamper-proof, even against us. Read [Security model](#security-model).


## Getting started: consuming entropy from a contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Definitions.sol";

struct UserState {
    EntropyRequest entropy_request;
    HashRecord hash_record;
}

contract ABCEntropyExample is IEntropyConsumer {
    IABCEntropy public abc_entropy;
    mapping(address => UserState) public user_state_map;
    event RandomEvent(address user, bytes32 random_number);

    constructor() {
        abc_entropy = IABCEntropy(0xd7Ca4e99F7C171B9ea2De80d3363c47009afaC5F);
    }

    function get_entropy(bytes32 user_entropy) external payable {
        bytes memory a_seed = abi.encodePacked(user_entropy, msg.sender);
        bytes32 entropy_a = keccak256(a_seed);
        UserState storage user_state = user_state_map[msg.sender];
        bytes32 callback_id = bytes32(uint256(uint160(msg.sender)));
        uint256 callback_gas_limit = 50000;
        uint256 fee = abc_entropy.get_fee(callback_gas_limit);
        user_state.entropy_request = abc_entropy.get{value: fee}(
            callback_id,
            callback_gas_limit,
            user_state.hash_record.id,
            entropy_a
        );
    }

    function entropy_callback(
        bytes32 callback_id, EntropyResponse calldata entropy_response
    ) external payable {
        require(msg.sender == address(abc_entropy), "INVALID_PROVIDER");
        address user = address(uint160(uint256(callback_id)));
        UserState storage user_state = user_state_map[user];
        Verified memory verified = abc_entropy.verify(
            user_state.hash_record.hash,
            user_state.entropy_request,
            entropy_response
        );
        if (verified.b || bytes32(0) == user_state.hash_record.hash) {
            user_state.hash_record = verified.next_hash_record;
            emit RandomEvent(user, verified.random_number);
        }
    }
}
```


```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Definitions.sol";

/**
 * @notice Stores the state associated with an individual user's entropy request and hash commitment
 */
struct UserState {
    EntropyRequest entropy_request;
    HashRecord hash_record;
}

/**
 * @title ABC Entropy Example Consumer Contract
 * @notice Example implementation demonstrating how client dApps integrate with the ABC entropy and commit-reveal system
 * @dev Implements IEntropyConsumer to handle incoming oracle callbacks and securely derive verifiable random numbers
 */
contract ABCEntropyExample is IEntropyConsumer {
    /**
     * @notice Reference to the core ABC Entropy oracle contract
     */
    IABCEntropy public abc_entropy;

    /**
     * @notice Mapping from user addresses to their respective request and commitment states
     */
    mapping(address => UserState) public user_state_map;

    /**
     * @notice Emitted when a verified random number is successfully generated and delivered to the user
     * @param user The address of the user who requested the randomness
     * @param random_number The final cryptographic random number derived from the entropy pair
     */
    event RandomEvent(address user, bytes32 random_number);

    /**
     * @notice Initializes the consumer contract with the ABC Entropy oracle address
     * @dev Note: The hardcoded address below is for Arbitrum Sepolia testing and must be updated for other networks.
     */
    constructor() {
        // Arbitrum Sepolia example address. This should be configured per target network.
        abc_entropy = IABCEntropy(0xd7Ca4e99F7C171B9ea2De80d3363c47009afaC5F);
    }

    /**
     * @notice Requests a random number on behalf of a user
     * @dev Combines user-provided entropy with msg.sender to ensure uniqueness, calculates the required fee, 
     *      retrieves callback parameters, and submits the request to the ABC Entropy oracle.
     * @param user_entropy Additional entropy seed supplied by the user
     */
    function get_entropy(bytes32 user_entropy) external payable {
        // Blend user-provided entropy with the sender's address to guarantee unique seeds across different users
        bytes memory a_seed = abi.encodePacked(user_entropy, msg.sender);
        bytes32 entropy_a = keccak256(a_seed);
        
        // Note: entropy_b is already fixed and protected behind a prior hash commitment at this point.
        // entropy_c is currently being generated.
        
        // Retrieve the user's state record (Note: production implementations should check for pending requests).
        UserState storage user_state = user_state_map[msg.sender];

        // Bind the callback identifier to the user's address so the oracle response can route it back correctly.
        bytes32 callback_id = bytes32(uint256(uint160(msg.sender)));

        // Define the gas limit allocated for the callback execution (can be statically pre-calculated based on logic).
        uint256 callback_gas_limit = 50000;
        
        // Compute the total fee required by the oracle contract.
        uint256 fee = abc_entropy.get_fee(callback_gas_limit);

        // Submit the request to the oracle, depositing the required fee and storing the returned EntropyRequest data.
        user_state.entropy_request = abc_entropy.get{value: fee}(
            callback_id,
            callback_gas_limit,
            user_state.hash_record.id,
            entropy_a
        );
    }

    /**
     * @notice Receives and processes the oracle's entropy callback response
     * @dev Validates the callback sender, retrieves the corresponding user state, verifies the entropy 
     *      response commitments, updates the hash record, and emits the final random number event.
     * @param callback_id The unique identifier routing the callback back to the originating user
     * @param entropy_response The response payload containing entropy values and next-round commitments
     */
    function entropy_callback(
        bytes32 callback_id, EntropyResponse calldata entropy_response
    ) external payable {
        // Ensure the callback is coming exclusively from the authorized ABC Entropy oracle contract.
        require(msg.sender == address(abc_entropy), "INVALID_PROVIDER");

        // Derive the original user address from the callback identifier.
        address user = address(uint160(uint256(callback_id)));
        UserState storage user_state = user_state_map[user];
        
        // Verify the received entropy response data against the stored hash commitment and request state.
        Verified memory verified = abc_entropy.verify(
            user_state.hash_record.hash,
            user_state.entropy_request,
            entropy_response
        );
        
        // Flag c may evaluate to false if the oracle response takes more than 8,191 blocks (highly unlikely).
        // If this occurs, off-chain verification can still be performed by inspecting event logs.
        if (!verified.c) {
            // Optional: handle delayed responses or fallback logging here.
        }

        // Proceed if flag b is true, or if this is the initial interaction (where the hash is bytes32(0)).
        // On this first call, b is false because there is no prior commitment, but saving verified.next_hash_record
        // establishes the first link in the hash chain, ensuring all subsequent requests have verified.b set to true.
        if (verified.b || bytes32(0) == user_state.hash_record.hash) {
            // Update the user's hash record with the next commitment for future rounds.
            user_state.hash_record = verified.next_hash_record;
            
            // Emit the generated random number to client listeners.
            emit RandomEvent(user, verified.random_number);
        }
    }
}
```

The full interface is in the [docs](https://docs.example.com).

## Features

- **Verifiable:** every number ships with a proof that anyone can check on-chain.
- **Fast:** results arrive in your callback within [X] seconds on supported chains.
- **Predictable cost:** the fee for a request is readable from the contract with `get_fee(callback_gas_limit)`.
- **Simple to integrate:** one request function, one callback. No off-chain infrastructure to run.

<!-- TODO: only keep claims you can back with numbers or links. -->

## Supported networks

| Network | Contract | Fee per request | Typical latency |
|---|---|---|---|
| Ethereum | `0x0000…0000` | 0.000 ETH | [X] s |
| Base | `0x0000…0000` | 0.000 ETH | [X] s |
| Arbitrum | `0x0000…0000` | 0.000 ETH | [X] s |

<!-- TODO: keep this table up to date; it is the part that will change most. -->

## Security model

Security model explanation...

## License

MIT © 2026 Nudge
