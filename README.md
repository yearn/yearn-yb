# Yearn YB Locker

A permissioned lock management system for Yearn Boost (YB) tokens with delegated voting capabilities.

## Architecture

The system consists of two main contracts:

### Locker
- Holds and locks YB tokens in the veYB (voting escrow) contract
- Provides generic execution interface for arbitrary calls
- Owned by governance, with operator delegation
- Pre-approves max tokens to escrow for gas efficiency

### Operator
- Delegates specific voting and lock management permissions
- Three permission tiers:
  - **Gauge Voters**: Can vote on gauge weights
  - **DAO Voters**: Can vote on DAO proposals
  - **Lockers**: Can lock/increase YB tokens
- All roles default to contract owner

## Usage

```solidity
// Deploy
Locker locker = new Locker(owner, ybToken, veYB);
Operator operator = new Operator(locker, gaugeController, daoVoting);
locker.setOperator(address(operator));

// Grant permissions
operator.setGaugeVoter(gaugeVoter, true);
operator.setDaoVoter(daoVoter, true);
operator.setLocker(lockerRole, true);
```

## Testing

Tests use Foundry with mainnet forking:

```bash
# Set RPC URL
export MAINNET_RPC_URL=<your-rpc-url>

# Run tests
forge test

# Run with verbosity
forge test -vvv
```

### CI Setup

To run tests in GitHub Actions:

1. Go to your repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `MAINNET_RPC_URL`
4. Value: Your mainnet RPC endpoint (e.g., Alchemy, Infura, or Llamarpc URL)
5. Click "Add secret"

The CI workflow will automatically use this secret when running tests.

## Development

Built with:
- Solidity ^0.8.20
- Foundry
- OpenZeppelin Contracts

See `.claude/CLAUDE.md` for testing standards.
