# ABC Entropy

**Verifiable, tamper-proof randomness for your smart contracts.**

ABC Entropy is a lightweight commit-reveal randomness oracle designed to deliver verifiable, on-chain random numbers to your dApp with minimal friction.

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
Below is an example consumer contract implementing `IEntropyConsumer` (see [`ABCEntropyExample.sol`](./ABCEntropyExample.sol) for the full source code and detailed inline comments):
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@pulsartronic/entropy/Definitions.sol";

struct UserState {
    EntropyRequest entropy_request;
    HashRecord hash_record;
}

contract ABCEntropyExample is IEntropyConsumer {
    IABCEntropy public abc_entropy;
    mapping(address => UserState) public user_state_map;
    event RandomEvent(address user, bytes32 random_number);

    constructor() {
        // Arbitrum Sepolia example address.
        abc_entropy = IABCEntropy(0xBfBfcbc03E3A3c40656b23fcfdb96A48232B8C3f);
    }

    function get_entropy(bytes32 user_entropy) external payable {
        bytes memory a_seed = abi.encodePacked(user_entropy, msg.sender);
        bytes32 entropy_a = keccak256(a_seed);
        UserState storage user_state = user_state_map[msg.sender];
        bytes32 callback_id = bytes32(uint256(uint160(msg.sender)));
        uint256 callback_gas_limit = 50000;
        uint256 fee = abc_entropy.get_fee(callback_gas_limit);

        // Request a randoom number.
        user_state.entropy_request = abc_entropy.get{value: fee}(
            callback_id,
            callback_gas_limit,
            user_state.hash_record.id,
            entropy_a
        );
    }

    function entropy_callback(bytes32 callback_id, EntropyResponse calldata entropy_response) external payable {
        require(msg.sender == address(abc_entropy), "INVALID_PROVIDER");
        address user = address(uint160(uint256(callback_id)));
        UserState storage user_state = user_state_map[user];

        // Get the requested random number.
        Verified memory verified = abc_entropy.verify(
            user_state.hash_record.hash,
            user_state.entropy_request,
            entropy_response
        );

        // Emit an event with the generated random number.
        if (verified.b || bytes32(0) == user_state.hash_record.hash) {
            user_state.hash_record = verified.next_hash_record;
            emit RandomEvent(user, verified.random_number);
        }
    }
}
```
## Quick Test Guide in Remix

1. **Open the Contract:** Click [Open in Remix](https://app.remix.live/pulsartronic/entropy/blob/main/ABCEntropyExample.sol).
2. **Compile:** Go to the **Solidity Compiler** tab on the left, select version `0.8.20` (or higher), and click **Compile ABCEntropyExample.sol**.
3. **Deploy & Test on Arbitrum Sepolia:**
   - Switch your Web3 wallet (MetaMask) to **Arbitrum Sepolia**.
   - Go to the **Deploy & Run Transactions** tab.
   - Set *Environment* to **Injected Provider - MetaMask**.
   - The contract is pre-configured with the testnet oracle address (`0xBfBfcbc03E3A3c40656b23fcfdb96A48232B8C3f`).
   - Call `get_entropy` passing some test bytes32 data (e.g., `0x1234...`) and attach the required ETH fee (check `get_fee` first if needed)!
  
## Features

- **Verifiable:** every number ships with a proof that anyone can check on-chain.
- **Fast:** results arrive in your callback within [X] seconds on supported chains.
- **Predictable cost:** the fee for a request is readable from the contract with `get_fee(callback_gas_limit)`.
- **Simple to integrate:** one request function, one callback. No off-chain infrastructure to run.

## Supported networks

### Mainnets
| Network | Contract |
|---|---|
| Ethereum | `0x0000000000000000000000000000000000000000` |
| Arbitrum | `0x0000000000000000000000000000000000000000` |

### Testnets
| Network | Contract |
|---|---|
| Ethereum | `0x492170C151777b7839d9c4cDD58448f0Deca9bcB` |
| Arbitrum | `0xBfBfcbc03E3A3c40656b23fcfdb96A48232B8C3f` |


## Security model

ABC Entropy relies on a cryptographically secure commit-reveal architecture designed to prevent any single party—including us, the service provider—from predicting, altering, or rigging the final outcome.

### How the Trust Guarantee Works

The final random number is derived by combining three independent entropy sources:

```random_number = keccak256(A, B, C)```

1. **Entropy A (The User/dApp):** Your frontend or user supplies their own entropy contribution during the request.
2. **Entropy B (The Provider Commitment):** We lock our entropy contribution behind a cryptographic hash before you make a request. Once committed, it is permanently locked and cannot be modified.
3. **Entropy C (The Sequencer):** An independent third-party network layer introduces block-level entropy at the moment your dApp makes a request.

### Defending Against Provider Manipulation

The core challenge in building a verifiable random number oracle is preventing us from acting as a privileged user within your dApp.

ABC Entropy neutralizes this threat through **Entropy C**:
- Because Entropy C is generated **after** our commitment (but before revealing it) and **after** your dApp request, neither you nor us nor the sequencer can know all A, B and C values in advance. 
- Even though we could know Entropies A and B in advance (by acting as a user), the unpredictable nature of C prevents any pre-calculation or manipulation of the final result.

### Trust Assumptions

This security model remains fully tamper-proof as long as the service provider (us) does not control the entity generating Entropy C.
We mitigate this risk by letting you choose your preferred sequencer from an open list —making it highly unlikely that a single provider controls all available options.

## License

MIT © 2026 pulsartronic
