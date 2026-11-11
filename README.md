# ABC Entropy

**Randomness your contract can prove.**

Pulsartronic delivers verifiable random numbers to your dapp, generated with ABC entropy and checkable on-chain.

---

## Table of contents

- [How ABC entropy works](#how-abc-entropy-works)
- [Getting started](#getting-started-consuming-entropy-from-a-contract)
- [Features](#features)
- [Supported networks](#supported-networks)
- [Security model](#security-model)

## How ABC entropy works

Nudge uses a commit-reveal scheme built on three components, each contributing part of the final random number:

| | Component | Role |
|---|---|---|
| **A** | Your dapp users | Your frontend provides the user's entropy contribution. |
| **B** | Generator (Nudge) | We lock our entropy contribution behind a hash beforehand, allowing post-reveal verification. |
| **C** | Sequencer (the network) | It introduces additional entropy so that no party, including us, can manipulate the outcome. |

Under the ABC model, as long as we aren't running the sequencer, the system remains entirely tamper-proof, even against us.

The biggest challenge in building a secure and verifiable random number generation service is protecting the customer from manipulation by the service provider itself. ABC entropy is designed around that problem.

## Getting started: consuming entropy from a contract

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@mrvifas/entropy/Definitions.sol";

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
        // This is a chance for adding user generated entropy
        // and make it different for different users sending the same user_entropy.
        bytes memory a_seed = abi.encodePacked(user_entropy, msg.sender);
        bytes32 entropy_a = sha256(a_seed);
        // entropy_b is already fixed and behind a hash at this point.
        // entropy_c is being generated.

        // Let's say we save entropy requests by user address
        // (notice we don't check for previous requests, you should).
        UserState storage user_state = user_state_map[msg.sender];

        // And bind callbacks in the same way. Entropy response will echo this value.
        bytes32 callback_id = bytes32(uint256(uint160(msg.sender)));

        // Example limit: callback_gas_limit depends on what you do in the response function.
        // It could be statically pre-calculated.
        uint256 callback_gas_limit = 50000;
        // Calculates fees.
        uint256 fee = scrypt_entropy.get_fee(callback_gas_limit);

        // Request a random number. It makes the call and returns an EntropyRequest struct
        // needed for verification.
        // You could check:
        //   a) entropy_request.seed == seed
        //   b) entropy_request.block_number == some_method_to_get_it
        // You can also check its public code at http://docs.com
        user_state.entropy_request = scrypt_entropy.abc_entropy{value: fee}(
            callback_id,
            callback_gas_limit,
            user_state.hash_record.id,
            entropy_a
        );
    }

    // Entropy response callback.
    function entropy_callback(
        bytes32 callback_id, EntropyResponse calldata entropy_response
    ) external payable {
        // Check who's calling this function, it's public.
        require(msg.sender == address(scrypt_entropy), "INVALID PROVIDER");

        // Obtain the corresponding UserState (remember this is an example).
        address user = address(uint160(uint256(callback_id)));
        UserState storage user_state = user_state_map[user];

        // Verify received data using our "verify" function.
        // If you want to use a different method read its
        // public code to see what it does at http://docs.com
        Verified memory verified = scrypt_entropy.verify(
            user_state.hash_record.hash,
            user_state.entropy_request,
            entropy_response
        );

        if (!verified.c) {
            // This can happen if this response took more than 8190 blocks, which is unlikely.
            // If this happens, you still have the chance to verify this operation off-chain.
            // Read the docs at http://docs.com
        }

        if (verified.b || bytes32(0) == user_state.hash_record.hash) {
            // Save next round commitment.
            user_state.hash_record = verified.next_hash_record;
            // Emit obtained random number...
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
