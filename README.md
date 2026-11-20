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
        abc_entropy = IABCEntropy(0x29A269640D240B4d08e74b2564832aEcA00484FC);
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

    function entropy_callback(
        bytes32 callback_id, EntropyResponse calldata entropy_response
    ) external payable {
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
        user_state.hash_record = verified.next_hash_record;
        emit RandomEvent(user, verified.random_number);
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
   - The contract is pre-configured with the testnet oracle address (`0x29A269640D240B4d08e74b2564832aEcA00484FC`).
   - Call `get_entropy` passing some test bytes32 data (e.g., `0x1234...`) and attach the required ETH fee (check `get_fee` first if needed)!
  
## Features

- **Verifiable:** every number ships with a proof that anyone can check on-chain.
- **Fast:** results arrive in your callback within a few seconds on supported chains.
- **Predictable cost:** the fee for a request is readable from the contract with `get_fee(callback_gas_limit)`.
- **Simple to integrate:** one request function, one callback. No off-chain infrastructure to run.

## Supported networks

### Mainnets
| Network | Contract |
|---|---|
| Arbitrum | `0x16C208E0e2B8Df76f11A7085B3e306A27455F9F9` |
| Base | `0x15f31ab7371C02E2a505f569Eea9057AA75CaBAB` |
| Optimism | `0x15f31ab7371C02E2a505f569Eea9057AA75CaBAB` |


### Testnets
| Network | Contract |
|---|---|
| Arbitrum | `0x29A269640D240B4d08e74b2564832aEcA00484FC` |
| Base | `0x16C208E0e2B8Df76f11A7085B3e306A27455F9F9` |
| Optimism | `0x16C208E0e2B8Df76f11A7085B3e306A27455F9F9` |


## Security model

ABC Entropy relies on a cryptographically secure commit-reveal architecture designed to prevent any single party from predicting, altering, or rigging the final outcome. The resulting random number is derived by combining three independent entropy sources:

```random_number = keccak256(A, B, C)```

Entropy A is the user contribution (a seed generated by your front-end dApp).  
Entropy B is our contribution, which we first publish as "hash(B)"  
Entropy C is the block hash in which your dApp sends A requesting B (It places A before C).  

### why

Mitigating external threats is "easy". The core challenge in building a verifiable random number oracle is preventing ourselves from acting as a privileged user within your dApp.

This threat is neutralized through **Entropy C**:

- Even though we could know Entropies A and B in advance (by acting as a user), we couldn't know C before we commit to A and B, which prevents any pre-calculation.
- Something similar would happen to the Sequencer where it could know Entropies A and C in advance, but not B.

### Trust Assumptions

This security model remains fully tamper-proof as long as the service provider (us) does not control the entity generating Entropy C (the sequencer).

We mitigate this risk by letting you choose your preferred sequencer from a (growing) list, making it unlikely that we control all available options. 

## License

MIT © 2026 pulsartronic
