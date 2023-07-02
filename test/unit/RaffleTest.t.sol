// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {CreateSubscription} from "../../script/Interaction.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "../mocks/VRFCoordinatorV2Mocks.sol";

contract RaffleTest is Test {
    ////////////
    // events //
    ////////////
    event EnteredRaffle(address indexed player);

    ///////////////
    // modifiers //
    ///////////////
    modifier PlayerFund() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: TICKET_FEES}();
        _;
    }

    modifier UpkeepNeeded() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: TICKET_FEES}();
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + interval + 1);
        _;
    }

    modifier SkipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    Raffle raffle;
    HelperConfig helperConfig;
    uint256 ticketFees;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10000 ether;
    uint256 public constant TICKET_FEES = 1 ether;

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
        (
            ticketFees,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
            deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (subscriptionId == 0) {
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(
                vrfCoordinator,
                deployerKey
            );
        }

        vm.deal(PLAYER, STARTING_BALANCE);
    }

    function testRaffleInitializesWithOpenState() public {
        // console.log(raffle.getRaffleState());
        console.log(uint256(raffle.getRaffleState()));
        assertEq(
            uint256(raffle.getRaffleState()),
            uint256(Raffle.RaffleState.OPEN)
        );
    }

    ///////////////////
    // enterRaffle() //
    ///////////////////
    function testRaffleRevrtsETHNotEnough() public {
        vm.expectRevert();
        raffle.enterRaffle();
    }

    function testRafflePlayersAreUpdated() public PlayerFund {
        assertEq(raffle.getPlayers(0), PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: TICKET_FEES}();
    }

    function testRaffleRevertsLotteryIsCurrentlyClosed() public UpkeepNeeded {
        raffle.performUpkeep();

        vm.expectRevert();
        vm.prank(PLAYER);
        raffle.enterRaffle{value: TICKET_FEES}();
    }

    ///////////////////
    // checkUpkeep() //
    ///////////////////
    function testCheckUpkeepReturnsTrueIfCondSatisfied() public UpkeepNeeded {
        (bool result, ) = raffle.checkUpkeep("");
        assertEq(result, true);
    }

    function testCheckUpkeepReturnsEmptyPerformData() public UpkeepNeeded {
        (, bytes memory performData) = raffle.checkUpkeep("");
        assertEq(performData, "0x0");
    }

    // function testCheckUpkeepReturnsFalseIfNOPlayers() public {
    //     vm.prank(PLAYER);
    //     raffle.enterRaffle{value: TICKET_FEES}();
    //     vm.roll(block.number + 1);
    //     vm.warp(block.timestamp + interval - 1);
    //     (bool result, ) = raffle.checkUpkeep("");
    //     assertEq(result, false);
    // }

    function testCheckUpkeepReturnsFalseIfNOTEnoughBalance() public PlayerFund {
        (bool result, ) = raffle.checkUpkeep("");
        console.log(raffle.getNumberOfPlayers());
        assertEq(result, false);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsClosed() public UpkeepNeeded {
        raffle.performUpkeep();

        (bool result, ) = raffle.checkUpkeep("");
        assertEq(result, false);
    }

    /////////////////////
    // performUpkeep() //
    /////////////////////
    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public PlayerFund {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + interval - 1); // ❌ -> So that "checkUpkeep()" returns FALSE.

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                TICKET_FEES,
                1,
                0
            )
        ); // ⚠️ -> We don't have any function link "expectNotRevert()"
        raffle.performUpkeep();
    }

    function testPerformUpkeepDoesNotRevertsIfCheckUpkeepIsTrue()
        public
        UpkeepNeeded
    {
        raffle.performUpkeep(); // ⚠️ -> We don't have any function link "expectNotRevert()"
    }

    function testPerformUpkeepEmitsRequestId() public UpkeepNeeded {
        vm.recordLogs();
        raffle.performUpkeep();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        /**
         * 🎯🎯
         * entries[0] -> emitted event in VRFCoordinatorV2Mock
         * entries[0] -> emitted event in Raffle.sol contract
         *
         * 🎯🎯
         * topics[0] -> refers to entire Event
         * topics[1] -> refers to indexed data & so on.....
         *
         * ⚠️⚠️ -> Each entry in Vm.Log[]: bytes32 format
         */
        bytes32 requestId = entries[1].topics[1];
        assert(uint256(requestId) > 0);
    }

    function testPerformUpkeepUpdatesRaffleState() public UpkeepNeeded {
        vm.recordLogs();
        raffle.performUpkeep();

        assert(uint256(raffle.getRaffleState()) > 0);
    }

    ////////////////////////
    // fulfillRandomWords //
    ////////////////////////

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public UpkeepNeeded SkipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomwordsTransferUpdateRaffleStateAndSetRecentWinner()
        public
        UpkeepNeeded
        SkipFork
    {
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < (startingIndex + additionalEntrants);
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, 10000 ether);
            raffle.enterRaffle{value: TICKET_FEES}();
        }

        uint256 total_prize = TICKET_FEES * (additionalEntrants + 1);
        uint256 startBalance = PLAYER.balance;

        // pretend to chainlink vrf and pick winner;
        // we need "consumer address" and "requestId"
        vm.recordLogs();
        raffle.performUpkeep();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 prevTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getNumberOfPlayers() == 0);
        assert(prevTimeStamp < raffle.getLastTimeStamp());

        assert(address(raffle).balance == 0); // 💰🪙 contract balance == 0
        assert(raffle.getRecentWinner().balance == startBalance + total_prize);
    }
}
