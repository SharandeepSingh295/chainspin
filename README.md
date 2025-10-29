# 🎯 ChainSpin - Transparent On-Chain Wheel Game

ChainSpin is a **simple, transparent, and verifiable on-chain wheel game** built using **Solidity**.  
It uses a **commit–reveal mechanism** to ensure that every spin outcome is fair and can be **independently verified** by anyone on the blockchain.

---

## 🧠 Project Description

**ChainSpin** is designed as an educational, beginner-friendly smart contract project that demonstrates how to build a transparent blockchain-based game.  
The contract allows players to place bets on numbers (0–36), similar to a roulette wheel.  
Once betting closes, the contract owner reveals a secret seed that was pre-committed earlier.  
Using that seed combined with a block hash, the final winning slot is **deterministically calculated**, ensuring no tampering or manipulation.

This project serves as a foundation for creating **provably fair blockchain games** and understanding **commit–reveal randomness** in Solidity.

---

## ⚙️ What It Does

1. **Owner opens a new game round** by committing a hash of a secret seed.  
2. **Players place bets** on any slot between 0 and 36 by sending ETH.  
3. After the betting period ends, **the owner reveals the seed**.  
4. The contract verifies the seed and calculates the **winning slot** using:
