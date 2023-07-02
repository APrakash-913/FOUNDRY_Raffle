// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title A Lottery Contract
 * @author Abhinav Prakash
 * @notice This contract is for creating Raffle.
 * @dev Implements Chainlink VRFv2 and Chainlink Automation
 */
contract Raffle is VRFConsumerBaseV2 {
    ////////////
    // ERRORS //
    ////////////
    error Raffle__NotEnoughETH();
    error Raffle__NotEnoughTimePassed();
    error Raffle__TxnFailed();
    error Raffle__LotteryIsCurrentlyClosed();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    //////////////////////
    // TYPE DECLARATION //
    //////////////////////
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }

    /////////////////////
    // STATE VARIABLES //
    /////////////////////

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    // @dev duration of Lottery in 'seconds'.
    uint256 private immutable i_interval;
    uint256 private immutable i_ticketFees;
    address private immutable i_vrfCoordinator;
    bytes32 private immutable i_keyHash;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    ////////////
    // EVENTS //
    ////////////

    event EnteredRaffle(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 _ticketFees,
        uint256 _interval,
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        i_ticketFees = _ticketFees;
        i_interval = _interval;
        i_vrfCoordinator = _vrfCoordinator;
        i_keyHash = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_ticketFees) {
            revert Raffle__NotEnoughETH();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__LotteryIsCurrentlyClosed();
        }
        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This Function is called by "Chainlink Automation" nodes call to see if it's time to perform Upkeep.
     * Following Should be true to return this:
     * 1. More than 0 players(Funds).
     * 2. Lottery should be open.
     * 3. Time Interval should have elapsed.
     * 4. Subscription is funded with LINK (Implicit).
     */
    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory performData) {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool lotteryIsOpen = (s_raffleState == RaffleState.OPEN);
        bool enoughPlayers = (s_players.length > 0);
        bool hasBalance = (address(this).balance > 0);

        upkeepNeeded = (timeHasPassed &&
            lotteryIsOpen &&
            enoughPlayers &&
            hasBalance);
        performData = "0x0";
    }

    // 1. want a Random Number
    // 2. use Random Number to pick a player
    // 3. automate it
    // function pickWinner() external {
    function performUpkeep() external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert Raffle__NotEnoughTimePassed();
        }

        // ⚠️ Before sending "request" to get "random_number". We need to close the Lottery
        s_raffleState = RaffleState.CALCULATING;

        // Get a random number.
        // 1️⃣ Request RNG.
        // 2️⃣ Get Random Number.

        uint256 requestId = VRFCoordinatorV2Interface(i_vrfCoordinator)
            .requestRandomWords(
                i_keyHash,
                i_subscriptionId,
                REQUEST_CONFIRMATIONS,
                i_callbackGasLimit,
                NUM_WORDS
            );

        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*_requestId*/,
        uint256[] memory _randomWords
    ) internal override {
        uint256 indexOfWinner = _randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;

        // ⚠️ Since we get the winner. We need to open the Lottery ➕ Reset s_players array ➕ Reset Timestamp
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        emit WinnerPicked(winner);

        // 🤑💸Transfer Reward
        (bool callSuccess, ) = winner.call{value: address(this).balance}("");

        if (!callSuccess) {
            revert Raffle__TxnFailed();
        }
    }

    /////////////
    // GETTERS //
    /////////////

    function getTicketFees() external view returns (uint256) {
        return i_ticketFees;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getPlayers(uint256 index) external view returns (address) {
        return s_players[index];
    }

    function getRequestConfirmation() external pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getVRFCoordinator() external view returns (address) {
        return i_vrfCoordinator;
    }

    function getKeyHash() external view returns (bytes32) {
        return i_keyHash;
    }

    function getSubscriptionId() external view returns (uint64) {
        return i_subscriptionId;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
