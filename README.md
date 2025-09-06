# 🏛️ BudgetDAO - Community Budget Voting

A decentralized autonomous organization (DAO) smart contract for community budget allocation and voting on the Stacks blockchain.

## 🌟 Features

- 💰 **Budget Management**: Initialize and track community budget funds
- 👥 **Member Management**: Add/remove voting members
- 📝 **Proposal Creation**: Submit funding proposals with detailed descriptions
- 🗳️ **Democratic Voting**: Members vote on budget proposals
- ⚡ **Automatic Execution**: Approved proposals automatically transfer funds
- 🔒 **Secure Governance**: Owner-controlled member management with decentralized voting

## 🚀 Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet for testing

### Installation

```bash
clarinet new budget-dao-project
cd budget-dao-project
```

Copy the contract code into `contracts/Budgetdao.clar`

## 📖 Usage

### 1. Initialize the DAO
```clarity
(contract-call? .Budgetdao initialize-budget u1000000) ;; 1 STX budget
```

### 2. Add Members
```clarity
(contract-call? .Budgetdao add-member 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### 3. Create a Proposal
```clarity
(contract-call? .Budgetdao create-proposal 
  "Community Park Upgrade" 
  "Install new playground equipment and benches" 
  u500000 
  'ST1RECIPIENT... 
  u144) ;; ~1 day voting period
```

### 4. Vote on Proposals
```clarity
(contract-call? .Budgetdao vote-on-proposal u1 true) ;; Vote YES
```

### 5. Execute Approved Proposals
```clarity
(contract-call? .Budgetdao execute-proposal u1)
```

## 🔧 Contract Functions

### Public Functions
- `initialize-budget(amount)` - Set initial budget (owner only)
- `add-member(member)` - Add voting member (owner only)
- `remove-member(member)` - Remove voting member (owner only)
- `create-proposal(title, description, amount, recipient, duration)` - Submit new proposal
- `vote-on-proposal(proposal-id, vote-for)` - Cast vote on proposal
- `execute-proposal(proposal-id)` - Execute approved proposal
- `fund-contract()` - Add funds to contract budget
- `set-min-votes(new-min)` - Set minimum votes required (owner only)

### Read-Only Functions
- `get-proposal(proposal-id)` - Get proposal details
- `get-vote(proposal-id, voter)` - Get specific vote
- `is-member(user)` - Check membership status
- `get-total-budget()` - Get current budget
- `get-proposal-count()` - Get total proposals created
- `get-min-votes-required()` - Get minimum votes needed
- `is-proposal-active(proposal-id)` - Check if proposal is still active
- `get-proposal-status(proposal-id)` - Get comprehensive proposal status

## 🧪 Testing

```bash
clarinet test
```

## 🏗️ Architecture

The contract uses three main data structures:
- **Proposals Map**: Stores all proposal details and voting results
- **Votes Map**: Tracks individual member votes to prevent double-voting
- **Member Status Map**: Manages DAO membership

## 🛡️ Security Features

- ✅ Owner-only administrative functions
- ✅ Member-only voting and proposal creation
- ✅ Double-voting prevention
- ✅ Proposal expiration checks
- ✅ Budget validation
- ✅ Execution prevention for failed proposals

## 📊 Governance Rules

- Minimum 3 votes required for proposal passage (configurable)
- Proposals must receive more YES than NO votes
- Only active members can vote and create proposals
- Proposals have time-limited voting periods
- Funds are automatically transferred upon execution

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

MIT License - feel free to use this for your community projects!


