//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
//as we inherited this vrf, we need to also inherit the constructor of the inherited codebase
/**
 * @title Raffle contract
 * @author tanisha
 * @notice this contract is for creating a sample raffle
 * @dev implements chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus{
    /* Errors */
    error Raffle_NotEnoughEth();
    error Raffle_TransferFailed();
    error RaffleNotOpen();
    error Raffle_UpKeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    /* Type Declarations*/

    //enum: fixed, readable states
    enum RaffleState{
        Open, Calculating
    }

    /* State Variables*/
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;
    address payable[] private s_players; //payable because one of the addresses will win the contest and will have to be paid
    address private s_recentWinner;
    RaffleState private s_raffleState;

    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS=1;


    /* Events*/
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(uint256 entranceFee, uint256 interval, address vrfCoordinator, bytes32 keyHash, uint256 subscriptionId, uint32 callbackGasLimit) VRFConsumerBaseV2Plus(vrfCoordinator){
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = keyHash;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.Open;
    }

    function enterRaffle() external payable {
        //require(msg.value >= i_entranceFee, "Full Fees aint paid!");
        // require(msg.value >= i_entranceFee , NotEnoughEth());
        if (msg.value < i_entranceFee) {
            revert Raffle_NotEnoughEth();
        }

        if(s_raffleState != RaffleState.Open){
            revert RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

/**
* @dev This is the function that the chainlink nodes will call to see if the lottery is ready to have a winner picked, the following should be true in order for upkeepNeeded to be true
* 1: The time interval has passed between raffle runs
* 2: The lottery is open
* 3: the contract has eth(funds)
* 4: Implicitly, your subscription has LINK
* @return upkeepNeeded - true if its time to restart the lottery
*/ 
    function checkUpkeep(bytes memory /* checkData */) public view returns (bool upkeepNeeded, bytes memory /* performData */){
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.Open;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }
   
    function performUpkeep(bytes calldata /* performData */) external {
        //get a random num
        //use the randome number to pick a player
        //be automatically called

        //check to see if enough time has passed to restart our lottery round automatically
        (bool upkeepNeeded, ) = checkUpkeep("");
        if(!upkeepNeeded){
            revert Raffle_UpKeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.Calculating;

        //get a random number from chainlink(off data)
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash, //this is basically the gas price
                subId: i_subscriptionId, //how we actually fund the oracle gas for working with chainlink vrf
                requestConfirmations: REQUEST_CONFIRMATIONS, //how many blocks we should wait for the chainlink to give us a random num
                callbackGasLimit: i_callbackGasLimit, //this is basically the gas limit
                numWords: NUM_WORDS, // how many random nums we want
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
            })
        );
        emit RequestedRaffleWinner(requestId);
    }


    // when we inherited VRFConsumerBaseV2Plus(an abstract contract), it expects you to override the function called fulfillRandomWords, without this ur contract is incomplete and must be marked abstract(which prevents deployment)
    //this function is marked virtual and internal in the base contract, which means you MUST override and define it in your Raffle contract. Until you do, Solidity considers your contract abstract and won’t compile it as deployable code.
    function fulfillRandomWords(uint256 /*requestId*/, uint256[] calldata randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.Open;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if(!success){
            revert Raffle_TransferFailed();
        }

        emit WinnerPicked(s_recentWinner);
    }


    /**
     * Getter Functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState){
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns(address){
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns(uint256){
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns(address){
        return s_recentWinner;
    }
}