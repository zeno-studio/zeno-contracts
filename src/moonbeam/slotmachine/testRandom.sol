// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "./Randomness.sol";
import {RandomnessConsumer} from "./RandomnessConsumer.sol";

/// modified from https://docs.moonbeam.network/tutorials/eth-api/randomness-lottery/

contract Lottery is RandomnessConsumer {
    // Randomness Precompile interface
    Randomness public randomness =
        Randomness(0x0000000000000000000000000000000000000809);
// The number of blocks before the request can be fulfilled (for Local VRF
// randomness). The MIN_VRF_BLOCKS_DELAY (from the Randomness Precompile) 
// provides a minimum number that is safe enough for games with low economical
// value at stake. Increasing the delay slightly reduces the probability 
// (already very low) of a collator being able to predict the pseudo-random number
    uint32 public VRF_BLOCKS_DELAY = MIN_VRF_BLOCKS_DELAY;  
// The gas limit allowed to be used for the fulfillment, which depends on the
// code that is executed and the number of words requested. Test and adjust
// this limit based on the size of the request and the processing of the 
// callback request in the fulfillRandomWords() function
    uint64 public FULFILLMENT_GAS_LIMIT = 100000;
// The minimum fee needed to start the lottery. This does not guarantee that 
// there will be enough fee to pay for the gas used by the fulfillment. 
// Ideally it should be over-estimated considering possible fluctuation of 
// the gas price. Additional fee will be refunded to the caller
    uint256 public MIN_FEE = FULFILLMENT_GAS_LIMIT * 150 gwei;  
// A string used to allow having different salt than other contracts
    bytes32 public SALT_PREFIX = "my_demo_salt_change_me";
// Stores the global number of requests submitted. This number is used as a
// salt to make each request unique


    uint256 public requestId;
// Which randomness source to use. This correlates to the values in the
// RandomnessSource enum in the Randomness Precompile
    uint256 public globalRequestCount;
// The number of winners. This number corresponds to how many random words
// will be requested. Cannot exceed MAX_RANDOM_WORDS (from the Randomness
// Precompile)
    Randomness.RandomnessSource randomnessSource;
    uint8 public NUM_RANDOM_WORDS = 2;
// The current request id

    constructor(
    Randomness.RandomnessSource source
) payable RandomnessConsumer() {
    // Because this contract can only perform one randomness request at a time,
    // we only need to have one required deposit

    randomnessSource = source;
    globalRequestCount = 0;
    // Set the requestId to the maximum allowed value by the precompile (64 bits)
    requestId = 2 ** 64 - 1;
}


function play() external payable {
    startRandomness();
}
/// getRequestStatus使用随机性预编译函数检查抽奖是否尚未开始。此函数返回RequestStatus枚举定义的状态。
///如果状态不是DoesNotExist，则抽奖已经开始

function startRandomness() internal  {
    // Check we haven't started the randomness request yet
    if (
        randomness.getRequestStatus(requestId) !=
        Randomness.RequestStatus.DoesNotExist
    ) {
        revert("Request already initiated");
    }

    // Check the fulfillment fee is enough
    uint256 fee = msg.value;
    if (fee < MIN_FEE) {
        revert("Not enough fee");
    }
    // Check there is enough balance on the contract to pay for the deposit.
    // This would fail only if the deposit amount required is changed in the
    // Randomness Precompile.
    uint256 requiredDeposit = randomness.requiredDeposit();
    if (address(this).balance < requiredDeposit) {
        revert("Deposit too low");
    }

    if (randomnessSource == Randomness.RandomnessSource.LocalVRF) {
        // Request random words using local VRF randomness
        requestId = randomness.requestLocalVRFRandomWords(
            msg.sender,
            fee,
            FULFILLMENT_GAS_LIMIT,
            SALT_PREFIX ^ bytes32(globalRequestCount++),
            NUM_RANDOM_WORDS,
            VRF_BLOCKS_DELAY
        );
    } else {
        // Requesting random words using BABE Epoch randomness
        requestId = randomness.requestRelayBabeEpochRandomWords(
            msg.sender,
            fee,
            FULFILLMENT_GAS_LIMIT,
            SALT_PREFIX ^ bytes32(globalRequestCount++),
            NUM_RANDOM_WORDS
        );
    }
}
/// 我们的fulfillRequest函数将调用随机性预编译的fulfillRequest方法。
/// 调用此方法时，在后台会调用随机性消费者的rawFulfillRandomWords方法，
/// 这将验证该调用是否源自随机性预编译。
/// 从那里，调用随机性消费者合约的fulfillRandomWords函数，
/// 并使用块的随机性结果和给定的盐计算所请求的随机字数，然后返回。如果履行成功，
/// FulfillmentSucceeded则会发出事件；否则，FulfillmentFailed将发出事件。

function fulfillRequest() public {
    randomness.fulfillRequest(requestId);
}

function fulfillRandomWords(
    uint256 /* requestId */,
    uint256[] memory randomWords
) internal override {
    pickWinners(randomWords);
}

function pickWinners(uint256[] memory randomWords) internal returns (uint256[] memory) {

    return randomWords; 
}

}