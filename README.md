# 🌐 NameMesh - Decentralized DNS Alternative

> A blockchain-based name registry system built on Stacks blockchain using Clarity smart contracts

## 🚀 Overview

NameMesh is a decentralized domain name system that allows users to register, manage, and resolve human-readable names on the blockchain. Think of it as a Web3 alternative to traditional DNS, where you truly own your domain names.

## ✨ Features

- 🏷️ **Name Registration**: Register unique names with custom resolvers
- 🔄 **Name Renewal**: Extend registration periods to maintain ownership
- 📤 **Name Transfer**: Transfer ownership to other users
- 🔧 **Resolver Management**: Update resolver addresses for your names
- 📝 **DNS Records**: Set custom DNS-like records (A, CNAME, TXT, etc.)
- 📊 **Name History**: Track ownership and action history
- 👤 **User Management**: View all names owned by a user
- ⏰ **Expiration System**: Names expire and become available for re-registration

## 💰 Pricing

- **Registration**: 1,000,000 microSTX (1 STX)
- **Renewal**: 500,000 microSTX (0.5 STX)
- **Registration Period**: 52,560 blocks (~1 year)

## 🛠️ Usage

### Register a Name

```clarity
(contract-call? .NameMesh register-name "myname" "https://myresolver.com")
```

### Renew a Name

```clarity
(contract-call? .NameMesh renew-name "myname")
```

### Transfer Name Ownership

```clarity
(contract-call? .NameMesh transfer-name "myname" 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Update Resolver

```clarity
(contract-call? .NameMesh update-resolver "myname" "https://newresolver.com")
```

### Set DNS Records

```clarity
(contract-call? .NameMesh set-record "myname" "A" "192.168.1.1")
(contract-call? .NameMesh set-record "myname" "CNAME" "example.com")
```

## 🔍 Query Functions

### Get Name Information

```clarity
(contract-call? .NameMesh get-name-info "myname")
```

### Check Name Owner

```clarity
(contract-call? .NameMesh get-name-owner "myname")
```

### Get User's Names

```clarity
(contract-call? .NameMesh get-user-names 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Get DNS Record

```clarity
(contract-call? .NameMesh get-record "myname" "A")
```

### Check if Name is Expired

```clarity
(contract-call? .NameMesh is-name-expired "myname")
```

## 📋 Name Requirements

- ✅ Minimum length: 3 characters
- ✅ Maximum length: 64 characters  
- ❌ No spaces allowed
- ✅ ASCII characters only

## 🏗️ Development

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet)
- [Stacks CLI](https://docs.stacks.co/docs/write-smart-contracts/cli-wallet-quickstart)

### Setup

```bash
clarinet new namemesh-project
cd namemesh-project
```

### Testing

```bash
clarinet test
```

### Deployment

```bash
clarinet deploy --testnet
```

## 🔐 Security Features

- ⚡ Owner-only functions for name management
- 🛡️ Expiration checks prevent unauthorized access
- 💸 Payment validation ensures proper fees
- 📜 Complete audit trail of all name actions

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License.

## 🌟 Roadmap

- [ ] Subdomain support
- [ ] Bulk operations
- [ ] Name marketplace
- [ ] Integration with existing DNS systems
- [ ] Mobile app interface

---


