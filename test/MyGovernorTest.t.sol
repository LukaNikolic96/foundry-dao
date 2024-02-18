// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {TimeLock} from "../src/TimeLock.sol";

contract MyGovernorTest is Test {
    MyGovernor governor;
    Box box;
    GovToken govToken;
    TimeLock timeLock;

    // we are creating fake user
    address public USER = makeAddr("user");
    uint256 public constant INITIAL_AMOUNT = 100 ether;


    address[] proposers;
    address[] executors;
    uint256[] values;
    bytes[] calldatas;
    address[] targets;


    // delay after the vote passes
    uint256 public constant MIN_DELAY = 3600; // 1 hour
    uint256 public constant VOTING_DELAY = 1; // 1 block until voting is active
    uint256 public constant VOTING_PERIOD = 50400; // 1 week

    function setUp() public {
        // we are creating gov token and mint it
        govToken = new GovToken();
        // we give initial amount to our user
        govToken.mint(USER, INITIAL_AMOUNT);

        vm.startPrank(USER);
        // we are giving full amount to user
        govToken.delegate(USER);

        // setting up timelock
        timeLock = new TimeLock(MIN_DELAY, proposers, executors);

        // setting up governor
        governor = new MyGovernor(govToken, timeLock);


        // SEtting some rules
        // time lock hashes rules so we use bytes32
        // only governor have proposer role
        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        // anyone can be executor
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        // we are admin
        bytes32 adminRole= timeLock.CANCELLER_ROLE();

        // only governor have this role
        timeLock.grantRole(proposerRole, address(governor));
        // address(0) means any address can do this
        timeLock.grantRole(executorRole, address(0));
        // user (we) is admin or canceller
        timeLock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        // we are transfering ownershim of box to time lock
        // timelock owns DAO and DAO owns timelock it is weird and confusing,
        // but in the end timelock have ultimate say where the stuff goes
        box.transferOwnership(address(timeLock));
    }

    // test to see that box should not be updated without governance
    function testBoxCantBeUpdatedWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
        /* Explanation-
        we are trying to call function store in box contract and update it to value 1, but
        that function onlyOwner can call and the owner is governance, so that is why we expect that
        line to revert and to not update store function */
    }

    // full test
    function testGovernanceUpdatesBox() public {
        // we are updating our box to new number 
        uint256 valueStore = 888;
        // then we create proposal
        // propose function in Governor.sol contract need 4 things :
        // target, value, calldata and description - they are all arrays as we put above
        string memory description = "store 1 in Box";
        // calldata encode functions so we want to call store function that takes uint256 and we call it with signature and value that it will store
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueStore);
        // we will not send values now
        values.push(0);
        calldatas.push(encodedFunctionCall);
        // our target will be box contract
        targets.push(address(box));

        // then we call proposal function
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // we want to view the state of our proposal
        console.log("Proposal state", uint256(governor.state(proposalId))); // should be 0 or pending

        // we will speedup time so we don't wait
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);

        
        console.log("Proposal state", uint256(governor.state(proposalId))); // should be 1 now or active

        // NOW WE VOTE
        string memory reason = "Sto pa da ne";

        uint8 voteWay = 1; // 1 is on position for(yes) - that proposal 

        // our USER is the one who vote
        vm.startPrank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);


        // speedup voting period
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Queue the TX
        // queue takes same parametres as proposal we just need to hash description
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        // speedup the delay after voting
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);
        // Execute
        governor.execute(targets,values,calldatas,descriptionHash);

        console.log("Box value:", box.getNumber());

        // now we check if it matches
        assert(box.getNumber() == valueStore);
    }
}
