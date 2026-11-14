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
(see [source code](./EntropyConsumerExample.sol) to see a commented version)
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

## Features

- **Verifiable:** every number ships with a proof that anyone can check on-chain.
- **Fast:** results arrive in your callback within [X] seconds on supported chains.
- **Predictable cost:** the fee for a request is readable from the contract with `get_fee(callback_gas_limit)`.
- **Simple to integrate:** one request function, one callback. No off-chain infrastructure to run.

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
