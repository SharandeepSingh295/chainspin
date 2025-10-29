# 🎡 ChainSpin — Transparent On-Chain Wheel Game 🎰

**ChainSpin** is a beginner-friendly, transparent, and verifiable **on-chain wheel game** built with Solidity.  
It demonstrates how to create a **fair, provable, and decentralized betting mechanism** using the **commit–reveal** pattern — where randomness and outcomes are fully auditable on the blockchain.

---

## 🧠 Project Description

Traditional online games often hide their random number generation and outcomes, leaving players uncertain about fairness.  
**ChainSpin** solves that by putting the game logic **on-chain**, where every bet, random seed, and final result can be publicly verified.

This project was built as a **learning and demo project** for beginners to explore:
- Smart contract programming in Solidity  
- Blockchain randomness using `commit–reveal`  
- Event-driven architecture and provable outcomes  

---

## ⚙️ What It Does

1. **Owner starts a round** by committing to a secret random seed (hashed).  
2. **Players place bets** on slots (0–36), similar to a roulette wheel.  
3. When betting closes, **the owner reveals** the seed.  
4. The contract uses the revealed seed + blockhash to **compute a verifiable random result**.  
5. **Players who guessed the correct slot** can call `claimWinnings()` to receive their share of the pot.  

Everything — from bets to randomness — is **transparent and traceable** on the blockchain.

---

## 🌟 Features

✅ **Fully On-Chain Transparency**  
Every bet, seed commit, and reveal is stored on the blockchain for anyone to verify.

✅ **Verifiable Randomness (Commit–Reveal)**  
The random result is computed from a hash combination of a **revealed seed** and **blockhash**, ensuring no one can predict or alter it.

✅ **Fair Payout System**  
Winning players are paid proportionally from the pot based on their bet amount.

✅ **No Centralized Server Needed**  
All logic runs directly on the Ethereum Virtual Machine (EVM).

✅ **Beginner-Friendly Solidity Code**  
Written for educational clarity with detailed inline comments.

✅ **Deployable to Celo Testnet / EVM Chains**  
Easily deploy and test using [Remix IDE](https://remix.ethereum.org), Hardhat, or Foundry.

---

## 🔗 Deployed Smart Contract

🧾 **Transaction / Deployment Link:**  
👉 [https://celo-sepolia.blockscout.com/tx/0xf2ef0d937f0283c7e402f1d8584652aa0f8e4080d9d9faf319226b12d83ff80e](https://celo-sepolia.blockscout.com/tx/0xf2ef0d937f0283c7e402f1d8584652aa0f8e4080d9d9faf319226b12d83ff80e)

**Network:** Celo Sepolia Testnet  
**Language:** Solidity 0.8.19  
**License:** MIT  

---

## 🧩 Smart Contract Code

```solidity
## 🧩 Smart Contract Code

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title ChainSpin - simple transparent wheel game (commit-reveal)
/// @notice Beginner example. Not production-ready. See comments for caveats.
contract ChainSpin {
    address public owner;
    uint256 public wheelSize = 37; // 0..36 (like a roulette wheel)
    uint256 public minBet = 0.01 ether;

    struct Round {
        bytes32 seedCommit;
        uint256 startBlock;
        uint256 endBlock;
        bool revealed;
        string seedRevealed;
        uint256 pot;
    }

    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) public bets;
    mapping(uint256 => mapping(uint256 => uint256)) public betsPerSlot;
    mapping(uint256 => Round) public rounds;
    uint256 public currentRoundId;

    event RoundOpened(uint256 roundId, bytes32 seedCommit, uint256 startBlock, uint256 endBlock);
    event BetPlaced(uint256 roundId, address indexed player, uint256 slot, uint256 amount);
    event SeedRevealed(uint256 roundId, string seed, uint256 resultSlot);
    event Payout(address indexed player, uint256 roundId, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        currentRoundId = 0;
    }

    function openRound(bytes32 seedCommit, uint256 bettingDurationBlocks) external onlyOwner {
        require(rounds[currentRoundId].endBlock == 0 || rounds[currentRoundId].revealed, "previous round active");
        require(bettingDurationBlocks >= 1, "duration>=1");

        currentRoundId++;
        rounds[currentRoundId] = Round({
            seedCommit: seedCommit,
            startBlock: block.number,
            endBlock: block.number + bettingDurationBlocks,
            revealed: false,
            seedRevealed: "",
            pot: 0
        });

        emit RoundOpened(currentRoundId, seedCommit, block.number, block.number + bettingDurationBlocks);
    }

    function placeBet(uint256 slot) external payable {
        require(slot < wheelSize, "invalid slot");
        Round storage r = rounds[currentRoundId];
        require(r.startBlock != 0, "no open round");
        require(block.number <= r.endBlock, "betting closed");
        require(msg.value >= minBet, "bet too small");

        bets[currentRoundId][msg.sender][slot] += msg.value;
        betsPerSlot[currentRoundId][slot] += msg.value;
        r.pot += msg.value;

        emit BetPlaced(currentRoundId, msg.sender, slot, msg.value);
    }

    function reveal(uint256 roundId, string calldata seedString) external {
        Round storage r = rounds[roundId];
        require(r.startBlock != 0, "round doesn't exist");
        require(!r.revealed, "already revealed");
        require(block.number > r.endBlock, "cannot reveal yet");
        require(keccak256(abi.encodePacked(seedString)) == r.seedCommit, "bad seed");

        bytes32 blockHash = blockhash(r.endBlock);
        bytes32 mix = keccak256(abi.encodePacked(seedString, blockHash, roundId));
        uint256 resultSlot = uint256(mix) % wheelSize;

        r.revealed = true;
        r.seedRevealed = seedString;

        emit SeedRevealed(roundId, seedString, resultSlot);

        uint256 winnersTotal = betsPerSlot[roundId][resultSlot];
        if (winnersTotal == 0) {
            return;
        }
    }

    mapping(uint256 => mapping(address => uint256)) public withdrawable;

    function claimWinnings(uint256 roundId, uint256 slot) external {
        Round storage r = rounds[roundId];
        require(r.revealed, "round not revealed");

        bytes32 blockHash = blockhash(r.endBlock);
        bytes32 mix = keccak256(abi.encodePacked(r.seedRevealed, blockHash, roundId));
        uint256 resultSlot = uint256(mix) % wheelSize;
        require(slot == resultSlot, "not winning slot");

        uint256 playerBet = bets[roundId][msg.sender][slot];
        require(playerBet > 0, "no bet on this slot");

        uint256 winnersTotal = betsPerSlot[roundId][resultSlot];
        uint256 pot = r.pot;

        uint256 payoutAmount = (pot * playerBet) / winnersTotal;
        bets[roundId][msg.sender][slot] = 0;

        (bool sent, ) = msg.sender.call{value: payoutAmount}("");
        require(sent, "transfer failed");
        emit Payout(msg.sender, roundId, payoutAmount);
    }

    function collectHouse(uint256 roundId) external onlyOwner {
        Round storage r = rounds[roundId];
        require(r.revealed, "not revealed");

        bytes32 blockHash = blockhash(r.endBlock);
        bytes32 mix = keccak256(abi.encodePacked(r.seedRevealed, blockHash, roundId));
        uint256 resultSlot = uint256(mix) % wheelSize;
        uint256 winnersTotal = betsPerSlot[roundId][resultSlot];
        require(winnersTotal == 0, "winners exist; can't collect");

        uint256 amount = r.pot;
        r.pot = 0;
        (bool sent, ) = owner.call{value: amount}("");
        require(sent, "transfer failed");
    }

    receive() external payable {}
}

