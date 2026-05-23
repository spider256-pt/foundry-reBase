# foundry-reBase



A cross-chain rebase token protocol with linear interest accrual, built and security-tested with Foundry. Integrates Chainlink CCIP for cross-chain token transfers.

---

## Overview

`foundry-reBase` implements a yield-bearing rebase token where user balances grow automatically over time through linear interest accrual. Users deposit ETH into a Vault and receive ReBase tokens that accrue interest every second based on a protocol-defined rate.

**Core Properties:**
- Linear interest accrual per second
- Principal balance preserved independently of accrued interest
- User-specific interest rates locked at deposit time
- Cross-chain transfers via Chainlink CCIP *(in progress)*
- Role-based access control for minting and burning

---

## Architecture

```
src/
├── ReBase.sol                  # Core rebase token with interest logic
│   ├── balanceOf()             # Dynamic balance = principal * growthFactor
│   ├── mint()                  # Mints tokens + accrues pending interest
│   ├── burn()                  # Burns tokens + accrues pending interest
│   ├── transfer()              # Transfers with interest rate inheritance
│   ├── setInterestRate()       # Owner-only global rate setter
│   └── _mintAccruedInterest()  # Internal interest settlement
│
├── Vault.sol                   # ETH deposit and redemption vault
│   ├── deposit()               # Accepts ETH, mints ReBase tokens 1:1
│   └── redeem()                # Burns ReBase tokens, returns ETH
│
└── interfaces/
    └── IReBaseToken.sol        # ReBase token interface

test/
└── FUZZ/
    └── RebaseToken.t.sol       # Full fuzz test suite (8 tests)
```

---

## How It Works

### Interest Accrual

Each user's balance grows linearly over time based on their locked interest rate:

```
growthFactor = PRECISION_FACTOR + (userInterestRate * timeElapsed)

balanceOf(user) = (principalBalance * growthFactor) / PRECISION_FACTOR
```

The interest rate is locked per user at the time of their first deposit. This ensures users are not penalised if the protocol owner reduces the global rate after their deposit.

### Interest Rate Inheritance

When a user transfers tokens to another address, the recipient inherits the **sender's locked interest rate**, not the current global rate. This protects recipients from receiving tokens at a lower rate than the sender originally locked in.

---

## Security

### Bug Found During Development

During fuzz testing, a critical accounting bug was discovered and fixed in `balanceOf`:

**Vulnerable (incorrect):**
```solidity
return principalBalance + growthFactor / PRECISION_FACTOR;
```

**Fixed (correct):**
```solidity
return (principalBalance * growthFactor) / PRECISION_FACTOR;
```

**Impact:** The incorrect formula added `PRECISION_FACTOR / PRECISION_FACTOR = 1` to every balance, including zero balances. This caused:
- Every address to have a phantom balance of `1` before any deposit
- `_mintAccruedInterest` to mint 1 extra token on every first deposit
- Burn operations to always leave a residual balance of `1`
- Users unable to fully redeem their positions

**Classification:** High severity — breaks core protocol invariant (users cannot fully exit)

---

## Test Suite

8 fuzz tests covering all core protocol invariants across 256+ randomised runs each.

| Test | Description |
|------|-------------|
| `testRedeemStraightAway` | Deposit then immediately redeem — balance must be 0 |
| `testRedeemAfterTimeWarp` | Redeem after interest accrual — user receives more ETH than deposited |
| `testDepositLinear` | Interest earned each period must be approximately equal (linear model) |
| `testTransfer` | Recipient inherits sender's locked interest rate, not global rate |
| `testCheckPrincipleBalanceAfterDeposit` | Principal equals deposit amount immediately after deposit |
| `testCheckPrincipleBalanceAfterTimeWarp` | Principal unchanged after time passes (only `balanceOf` grows) |
| `testUserCannotSetInterestRate` | Non-owner cannot call `setInterestRate` |
| `testNonGrantedUserCannotMintOrBurn` | Unauthorised addresses cannot mint or burn |

### Running Tests

```bash
# Clone the repository
git clone https://github.com/spider256-pt/foundry-reBase
cd foundry-reBase

# Install dependencies
forge install

# Run all tests
forge test

# Run with verbosity
forge test -vvvv

# Run specific test
forge test --match-test testRedeemStraightAway -vvvv

# Run fuzz tests with more runs
forge test --fuzz-runs 10000
```

---

## Installation

```bash
# Prerequisites: Foundry installed
# https://getfoundry.sh/

git clone https://github.com/spider256-pt/foundry-reBase
cd foundry-reBase
forge install
forge build
```

---

## Key Concepts

### Principal Balance vs Dynamic Balance

The protocol tracks two distinct balance concepts:

- **Principal Balance** (`principleBalnceOf`) — the raw token amount stored in contract storage, unchanged by time
- **Dynamic Balance** (`balanceOf`) — the actual redeemable balance including all accrued interest, calculated on the fly

```solidity
// Principal — what's in storage
uint256 principal = super.balanceOf(user);

// Dynamic — what the user can actually redeem
uint256 dynamic = (principal * growthFactor) / PRECISION_FACTOR;
```

### Interest Rate Locking

```solidity
function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
    _mintAccruedInterest(_to);
    s_userInterestRate[_to] = s_interestRate; // locked at mint time
    _mint(_to, _amount);
}
```

Once a user deposits, their rate is locked. The owner can lower the global rate for future depositors without affecting existing holders.

---

## Project Status

- [x] ReBaseToken contract
- [x] Vault contract
- [x] 8 fuzz tests — all passing
- [x] Bug discovered and fixed (balanceOf formula)
- [ ] Chainlink CCIP cross-chain integration *(in progress)*

---

## Author

**Pratik Das** — spider256-pt
Blockchain Security Auditor | Penetration Tester | Bhubaneswar, India

GitHub: https://github.com/spider256-pt
LinkedIn: https://linkedin.com/in/pratik-das-057a412a9
Medium: https://spider-256.medium.com

---

## License

MIT
