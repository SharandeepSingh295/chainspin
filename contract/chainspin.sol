// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title ChainSpin - simple transparent wheel game (commit-reveal)
/// @notice Beginner example. Not production-ready. See comments for caveats.
contract ChainSpin {
    address public owner;
    uint256 public wheelSize = 37; // 0..36 (like a roulette wheel)
    uint256 public minBet = 0.01 ether;

    struct Round {
        bytes32 seedCommit;    // hash(commitSeed)
        uint256 startBlock;    // block number when round opened for bets
        uint256 endBlock;      // block number after which reveal is allowed
        bool revealed;
        string seedRevealed;   // revealed seed (string for readability)
        uint256 pot;           // total betted in this round
    }

    // bets: mapping roundId => player => amount on chosen slot
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) public bets;
    // track total bets per slot
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
        // initialize first round as closed, owner must open
        currentRoundId = 0;
    }

    /// @notice Owner opens a new round by committing to a seed hash.
    /// @param seedCommit keccak256(abi.encodePacked(seedString))
    /// @param bettingDurationBlocks how many blocks betting is allowed
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

    /// @notice Players place bets on a slot (0..wheelSize-1). Bet amounts are sent as msg.value.
    /// @param slot chosen slot number
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

    /// @notice Owner reveals the seed. Anyone can call; reveal allowed only after betting closed.
    /// @param roundId the round to reveal
    /// @param seedString the plain-text seed the owner committed to earlier
    function reveal(uint256 roundId, string calldata seedString) external {
        Round storage r = rounds[roundId];
        require(r.startBlock != 0, "round doesn't exist");
        require(!r.revealed, "already revealed");
        require(block.number > r.endBlock, "cannot reveal yet");
        // verify commit
        require(keccak256(abi.encodePacked(seedString)) == r.seedCommit, "bad seed");

        // compute a verifiable random value using the seed + blockhash of the endBlock
        // NOTE: blockhash only works for the 256 most recent blocks, and blockhash can be manipulated,
        // but combining with owner seed commit gives public verifiability.
        bytes32 blockHash = blockhash(r.endBlock);
        // In some rare cases blockhash could be zero (old block), but for this example we accept it.
        bytes32 mix = keccak256(abi.encodePacked(seedString, blockHash, roundId));
        uint256 resultSlot = uint256(mix) % wheelSize;

        r.revealed = true;
        r.seedRevealed = seedString;

        emit SeedRevealed(roundId, seedString, resultSlot);

        // pay winners: simple equal-proportional payout (winner gets pot * (theirBet/totalWinnersBet))
        uint256 winnersTotal = betsPerSlot[roundId][resultSlot];
        if (winnersTotal == 0) {
            // no winners: owner collects the pot (house edge). For transparency emit event but no transfer.
            // In production you'd set a different policy.
            return;
        }

        // iterate naive: for demo only (inefficient for many players)
        // For simplicity, we make a single-pass payout by scanning possible players — not implemented here
        // as scanning on-chain is expensive. Instead we expose function for players to withdraw their winnings.
        // We'll record pot and winnersTotal and let winners withdraw individually.
        // For that we store winnersTotal and pot is already stored. We'll use a separate mapping for withdrawable balances.
        // (See withdrawWinnings below)
        // Save the winning slot totals in a helper mapping by reusing betsPerSlot and rounds[roundId].pot.
        // No extra state needed here.
    }

    // mapping round => player => withdrawable amount
    mapping(uint256 => mapping(address => uint256)) public withdrawable;

    /// @notice Players calculate and claim their winnings for a revealed round.
    /// @dev This function computes payout on-demand to avoid costly iteration when revealing.
    /// @param roundId the round to claim from
    /// @param slot the slot the player bet on (must match winning slot)
    function claimWinnings(uint256 roundId, uint256 slot) external {
        Round storage r = rounds[roundId];
        require(r.revealed, "round not revealed");
        // compute result slot deterministically (recompute using revealed seed)
        bytes32 blockHash = blockhash(r.endBlock);
        bytes32 mix = keccak256(abi.encodePacked(r.seedRevealed, blockHash, roundId));
        uint256 resultSlot = uint256(mix) % wheelSize;
        require(slot == resultSlot, "not winning slot");

        uint256 playerBet = bets[roundId][msg.sender][slot];
        require(playerBet > 0, "no bet on this slot");

        uint256 winnersTotal = betsPerSlot[roundId][resultSlot];
        uint256 pot = r.pot;

        // payout proportionally: player gets pot * playerBet / winnersTotal
        uint256 payoutAmount = (pot * playerBet) / winnersTotal;

        // zero out player's bet to avoid double claim
        bets[roundId][msg.sender][slot] = 0;

        // transfer payout
        (bool sent, ) = msg.sender.call{value: payoutAmount}("");
        require(sent, "transfer failed");
        emit Payout(msg.sender, roundId, payoutAmount);
    }

    /// @notice Owner can withdraw leftover funds (house edge) for rounds that had no winners.
    function collectHouse(uint256 roundId) external onlyOwner {
        Round storage r = rounds[roundId];
        require(r.revealed, "not revealed");
        // compute result
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

    /// @notice Fallback to receive tips
    receive() external payable {}
}

