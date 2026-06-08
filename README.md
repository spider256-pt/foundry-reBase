```markdown
# foundry-reBase

A cross-chain yield-bearing rebase token protocol featuring linear interest accrual. Built and security-tested with Foundry, integrating Chainlink Cross-Chain Interoperability Protocol (CCIP) to securely bridge liquidity across multiple EVM networks.

---

## 📖 Overview

`foundry-reBase` implements a yield-bearing rebase token where user balances grow automatically over time through linear interest accrual. Users deposit native assets into a Vault and receive ReBase tokens that accrue interest every second based on a protocol-defined rate. 

By leveraging Chainlink CCIP and a custom Token Pool architecture, users can burn tokens on a source chain, pass messages securely over the Decentralized Oracle Network (DON), and mint matching yield-bearing assets on a destination chain without breaking interest accrual tracking.

**Core Properties:**
- **Linear Interest:** Accrual calculated per second.
- **Principal Preservation:** Raw balances are preserved independently of accrued interest factors.
- **Immutable Rates:** User-specific interest rates are locked securely at the time of deposit.
- **Cross-Chain Native:** Token transfers via custom Chainlink CCIP token pools.
- **Strict Access Control:** Role-Based Access Control (RBAC) governing mint, burn, and pool operations.

---

## 🏗️ Architecture

```text
src/
├── ReBase.sol                  # Core rebase token with dynamic interest logic
│   ├── balanceOf()             # Dynamic balance = principal * growthFactor
│   ├── mint()                  # Mints tokens + accrues pending interest
│   ├── burn()                  # Burns tokens + accrues pending interest
│   ├── transfer()              # Transfers with interest rate inheritance
│   ├── setInterestRate()       # Owner-only global rate setter
│   └── _mintAccruedInterest()  # Internal interest settlement
│
├── Vault.sol                   # Native asset deposit and redemption vault
│   ├── deposit()               # Accepts ETH, mints ReBase tokens 1:1
│   └── redeem()                # Burns ReBase tokens, returns ETH
│
├── RebaseTokenPool.sol         # Chainlink CCIP Custom Pool for cross-chain mint/burn
│
└── interfaces/
    └── IReBaseToken.sol        # ReBase token interface

script/
├── Deployer.s.sol              # Core infrastructure deployment pipeline
├── ConfigurePool.s.sol         # CCIP Token Pool onboarding & configuration script
└── BridgeScript.s.sol          # Cross-chain bridging transaction automation

test/
├── FUZZ/
│   └── RebaseToken.t.sol       # Core mathematical variant fuzz suite (8 tests)
└── FORK/
    └── CrossChain.t.sol        # Multi-fork end-to-end CCIP simulation suite

```

---

## ⚙️ How It Works

### Interest Accrual

Each user's balance grows linearly over time based on their locked interest rate. The calculation executes entirely on-chain without looping:

```text
growthFactor = PRECISION_FACTOR + (userInterestRate * timeElapsed)

balanceOf(user) = (principalBalance * growthFactor) / PRECISION_FACTOR

```

The interest rate is locked per user at the time of their first deposit. This ensures users are not penalized if the protocol owner reduces the global rate after their initial deposit.

### Interest Rate Inheritance

When a user transfers tokens to another address, the recipient inherits the **sender's locked interest rate**, not the current global rate. This protects recipients from receiving tokens at a lower rate than the sender originally locked in.

### Cross-Chain Token Pool (CCIP)

To move tokens across chains safely, standard token bridging defaults to locking up collateral. This protocol instead utilizes a custom **Burn-and-Mint** wrapper layout through `RebaseTokenPool.sol`. When bridging cross-chain, tokens are burned on the source chain to lock in current accrued rewards, and minted freshly on the destination chain while preserving structural compatibility rules.

---

## 🛡️ Security

### Bug Found During Development

During fuzz testing, a critical accounting bug was discovered and fixed in the `balanceOf` view function:

**Vulnerable (incorrect):**

```solidity
return principalBalance + growthFactor / PRECISION_FACTOR;

```

**Fixed (correct):**

```solidity
return (principalBalance * growthFactor) / PRECISION_FACTOR;

```

**Impact:** The incorrect formula added `PRECISION_FACTOR / PRECISION_FACTOR = 1` to every balance, including zero balances. This caused:

* Every address to have a phantom balance of `1` before any deposit.
* `_mintAccruedInterest` to mint 1 extra token on every first deposit.
* Burn operations to always leave a residual balance of `1`.
* Users being unable to fully redeem their positions.

**Classification:** High severity — broke the core protocol invariant (users could not fully exit).

---

## 🧪 Test Suite

The repository contains an exhaustive test strategy combining fast state invariant testing with live multi-fork mainnet simulations.

### 1. Core Fuzzing Invariants (`test/FUZZ`)

8 fuzz tests covering all core protocol invariants across randomized runs.

| Test | Description |
| --- | --- |
| `testRedeemStraightAway` | Deposit then immediately redeem — balance must be 0 |
| `testRedeemAfterTimeWarp` | Redeem after interest accrual — user receives more asset than deposited |
| `testDepositLinear` | Interest earned each period must be approximately equal (linear model) |
| `testTransfer` | Recipient inherits sender's locked interest rate, not global rate |
| `testCheckPrincipleBalanceAfterDeposit` | Principal equals deposit amount immediately after deposit |
| `testCheckPrincipleBalanceAfterTimeWarp` | Principal unchanged after time passes (only `balanceOf` grows) |
| `testUserCannotSetInterestRate` | Non-owner cannot call `setInterestRate` |
| `testNonGrantedUserCannotMintOrBurn` | Unauthorized addresses cannot mint or burn |

### 2. Multi-Fork Integration Testing (`test/FORK`)

Comprehensive cross-chain testing suite (`CrossChain.t.sol`) simulating live token bridge traffic, pool registrations, and message handling logic using localized environment simulation engines.

### Running Tests

```bash
# Clone the repository
git clone [https://github.com/spider256-pt/foundry-reBase](https://github.com/spider256-pt/foundry-reBase)
cd foundry-reBase

# Install dependencies
forge install

# Run all units and fuzz assertions
forge test

# Run multi-fork integration suites
forge test --match-path test/FORK/* -vvvv

# Run fuzz tests with aggressive iterations
forge test --fuzz-runs 10000

```

---

## 🚀 Installation & Compilation

```bash
# Prerequisites: Foundry installed ([https://getfoundry.sh/](https://getfoundry.sh/))
git clone [https://github.com/spider256-pt/foundry-reBase](https://github.com/spider256-pt/foundry-reBase)
cd foundry-reBase
forge install
forge build

```

---

## 🧠 Key Concepts

### Principal Balance vs Dynamic Balance

The protocol tracks two distinct balance concepts to optimize gas and prevent storage bloat:

* **Principal Balance** (`principleBalanceOf`): The raw token amount stored in contract storage, unchanged by time.
* **Dynamic Balance** (`balanceOf`): The actual redeemable balance including all accrued interest, calculated strictly on the fly.

```solidity
// Principal — what's in storage
uint256 principal = super.balanceOf(user);

// Dynamic — what the user can actually redeem
uint256 dynamic = (principal * growthFactor) / PRECISION_FACTOR;

```

---

## 📌 Project Status

* [x] ReBaseToken contract architecture.
* [x] Native asset allocation Vault contract.
* [x] 8 core mathematical invariant fuzz tests.
* [x] Bug discovered and fixed (balanceOf formula structural risk).
* [x] Chainlink CCIP custom RebaseTokenPool implementation.
* [x] Deploy and configuration script suites.
* [x] Multi-Fork Cross-Chain End-to-End integration test suite.

---

## 👨‍💻 Author

**Pratik Das** — spider256-pt

Security Engineer | Penetration Tester | Bhubaneswar, India

* **GitHub:** [spider256-pt](https://github.com/spider256-pt)
* **LinkedIn:** [Pratik Das](https://linkedin.com/in/pratik-das-057a412a9)
* **Medium:** [@spider-256](https://spider-256.medium.com)

---
