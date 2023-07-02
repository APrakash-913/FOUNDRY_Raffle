// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "../test/mocks/VRFCoordinatorV2Mocks.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

////////////////////////
// CreateSubscription //
////////////////////////
contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , , uint256 deployerKey) = helperConfig
            .activeNetworkConfig();
        return createSubscription(vrfCoordinator, deployerKey);
    }

    function createSubscription(
        address vrfCoordinator,
        uint256 deployerKey
    ) public returns (uint64) {
        console.log("Creating subscription on ChainId", block.chainid);
        vm.startBroadcast(deployerKey); // 🔏 Passing Private🔑 to "Broadcast"
        uint64 sub_Id = VRFCoordinatorV2Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Your SubId is:", sub_Id);
        console.log("Update your subscriptionId in HelperConfig.s.sol");
        return sub_Id;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

//////////////////////
// FundSubscription //
//////////////////////
contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 sub_Id,
            ,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        fundSubscription(vrfCoordinator, sub_Id, link, deployerKey);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint64 subId,
        address link,
        uint256 deployerKey
    ) public {
        console.log("Funding subscription:", subId);
        console.log("using vrfCoordinator:", vrfCoordinator);
        console.log("On Chainid:", block.chainid);

        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey); // 🔏 Passing Private🔑 to "Broadcast"
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(
                subId,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey); // 🔏 Passing Private🔑 to "Broadcast"
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

/////////////////
// AddConsumer //
/////////////////
contract AddConsumer is Script {
    function addConsumerUsingConfig(address _raffleAddress) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 sub_Id,
            ,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        addConsumer(_raffleAddress, vrfCoordinator, sub_Id, deployerKey);
    }

    function addConsumer(
        address _raffleAddress,
        address _vrfCoordinator,
        uint64 _subId,
        uint256 _deployerKey
    ) public {
        console.log("Adding Conumer Contract: ", _raffleAddress);
        console.log("Using vrfCoordinator: ", _vrfCoordinator);
        console.log("On ChainId: ", block.chainid);

        vm.startBroadcast(_deployerKey); // 🔏 Passing Private🔑 to "Broadcast"
        VRFCoordinatorV2Mock(_vrfCoordinator).addConsumer(
            _subId,
            _raffleAddress
        );
        vm.stopBroadcast();
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );

        addConsumerUsingConfig(raffle);
    }
}
