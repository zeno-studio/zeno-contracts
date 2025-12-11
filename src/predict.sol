// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// UMA Optimistic Oracle V3 Interface (based on standard)
interface OptimisticOracleV3Interface {
    struct Request {
        address proposer;
        address disputer;
        IERC20 currency;
        bool settled;
        int256 proposedPrice;
        int256 resolvedPrice;
        uint256 expirationTime;
        uint256 reward;
        uint256 finalFee;
        uint256 bond;
        uint256 customLiveness;
    }

    function assertTruth(
        bytes calldata claim,
        address asserter,
        address callbackRecipient,
        address escalationManager,
        uint64 liveness,
        IERC20 currency,
        uint256 bond,
        bytes32 identifier,
        bytes32 domainId
    ) external returns (bytes32 assertionId);

    function disputeAssertion(bytes32 assertionId, address disputer) external;

    function settleAssertion(bytes32 assertionId) external;

    function getAssertion(bytes32 assertionId) external view returns (Request memory);
}

contract PredictionMarketWithUMA is Ownable {
    IERC20 public dai; // DAI token
    IERC721 public nft; // Existing NFT contract, token IDs 1-9999
    OptimisticOracleV3Interface public umaOracle; // UMA OO V3 on Linea (assume deployed)

    uint256 public constant PRIZE_POOL_RATE = 90; // 90% prize pool
    uint256 public constant KOL_RATE = 7; // 7% for KOLs
    uint256 public constant PLATFORM_RATE = 2; // 2% for platform
    uint256 public constant ORACLE_RATE = 1; // 1% for oracle (truth provider)

    uint256 public constant ORACLE_BOND = 100 * 10**18; // 100 DAI bond for asserter
    uint256 public constant DISPUTE_BOND = 500 * 10**18; // 500 DAI for disputer (UMA handles slashing)

    uint256 public constant UNIT_PRICE = 1 * 10**18; // 1 DAI per unit
    uint256 public constant DISCOUNT_RATE = 3; // 3% discount
    uint256 public constant DISCOUNTED_PRICE = UNIT_PRICE * 97 / 100; // 0.97 DAI

    uint256 public constant DEFAULT_LIVENESS = 7200; // 2 hours in seconds for UMA

    bytes32 public constant IDENTIFIER = keccak256("PREDICTION_OUTCOME"); // UMA identifier

    struct Event {
        string question;
        uint256 endTime;
        uint256 totalVolume; // Total betting volume in units
        uint256 yesVolume; // Yes bets in units
        uint256 noVolume; // No bets in units
        uint256 initiatorTokenId; // Initiator's token ID (for x2 contribution)
        mapping(uint256 => uint256) sampledVolume; // tokenId => sampled betting volume (units)
        uint256[] participatingTokenIds; // All token IDs that participated (for allocation)
        bool resolved;
        bool outcome; // True for YES, False for NO
        bytes32 assertionId; // UMA assertion ID
    }

    uint256 public eventCounter;
    mapping(uint256 => Event) public events;
    mapping(uint256 => mapping(address => uint256)) public userYesBets; // eventId => user => yes units
    mapping(uint256 => mapping(address => uint256)) public userNoBets; // eventId => user => no units

    event EventCreated(uint256 indexed eventId, string question, uint256 endTime, uint256 initiatorTokenId);
    event BetPlaced(uint256 indexed eventId, address bettor, bool outcome, uint256 units, uint256 tokenIdUsed);
    event TruthAsserted(uint256 indexed eventId, bytes32 assertionId, bool proposedOutcome);
    event AssertionDisputed(uint256 indexed eventId, bytes32 assertionId);
    event EventResolved(uint256 indexed eventId, bool outcome);
    event PrizeClaimed(uint256 indexed eventId, address claimant, uint256 amount);
    event KolClaimed(uint256 indexed eventId, uint256 tokenId, uint256 amount);
    event OracleClaimed(uint256 indexed eventId, address claimant, uint256 amount);

    constructor(address _dai, address _nft, address _umaOracle) Ownable(msg.sender) {
        dai = IERC20(_dai);
        nft = IERC721(_nft);
        umaOracle = OptimisticOracleV3Interface(_umaOracle);
        dai.approve(_umaOracle, type(uint256).max); // Approve UMA for bonds
    }

    // Create event (only NFT holders)
    function createEvent(string memory question, uint256 endTime, uint256 tokenId) external {
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(tokenId >= 1 && tokenId <= 9999, "Invalid token ID");
        require(endTime > block.timestamp, "End time in past");

        eventCounter++;
        Event storage evt = events[eventCounter];
        evt.question = question;
        evt.endTime = endTime;
        evt.initiatorTokenId = tokenId;
        evt.participatingTokenIds.push(tokenId); // Initiator auto-participates

        emit EventCreated(eventCounter, question, endTime, tokenId);
    }

    // Join event as participant (other NFT holders)
    function joinEvent(uint256 eventId, uint256 tokenId) external {
        Event storage evt = events[eventId];
        require(block.timestamp < evt.endTime, "Event ended");
        require(nft.ownerOf(tokenId) == msg.sender, "Not NFT owner");
        require(tokenId >= 1 && tokenId <= 9999, "Invalid token ID");
        require(tokenId != evt.initiatorTokenId, "Initiator already in");

        bool joined = false;
        for (uint i = 0; i < evt.participatingTokenIds.length; i++) {
            if (evt.participatingTokenIds[i] == tokenId) {
                joined = true;
                break;
            }
        }
        require(!joined, "Already joined");

        evt.participatingTokenIds.push(tokenId);
    }

    // Place bet
    function placeBet(uint256 eventId, bool outcome, uint256 units, uint256 referrerTokenId) external {
        Event storage evt = events[eventId];
        require(block.timestamp < evt.endTime, "Event ended");
        require(units > 0, "Zero units");

        uint256 payment = units * UNIT_PRICE;
        bool discountApplied = false;
        if (referrerTokenId >= 1 && referrerTokenId <= 9999 && nft.ownerOf(referrerTokenId) != address(0)) {
            bool isParticipant = false;
            for (uint i = 0; i < evt.participatingTokenIds.length; i++) {
                if (evt.participatingTokenIds[i] == referrerTokenId) {
                    isParticipant = true;
                    break;
                }
            }
            if (isParticipant) {
                payment = units * DISCOUNTED_PRICE;
                evt.sampledVolume[referrerTokenId] += units; // Full units count for sampling
                discountApplied = true;
            }
        }

        dai.transferFrom(msg.sender, address(this), payment);
        evt.totalVolume += units;
        if (outcome) {
            evt.yesVolume += units;
            userYesBets[eventId][msg.sender] += units;
        } else {
            evt.noVolume += units;
            userNoBets[eventId][msg.sender] += units;
        }

        emit BetPlaced(eventId, msg.sender, outcome, units, referrerTokenId);
    }

    // Assert truth via UMA (anyone, pays bond)
    function assertTruth(uint256 eventId, bool proposedOutcome) external {
        Event storage evt = events[eventId];
        require(block.timestamp > evt.endTime, "Event not ended");
        require(evt.assertionId == 0, "Assertion exists");

        // Construct claim
        bytes memory claim = abi.encodePacked("Outcome for event ", eventId, " is ", proposedOutcome ? "YES" : "NO");
        bytes memory ancillaryData = abi.encodePacked("EventID:", eventId, evt.question);

        // Assert via UMA OO V3
        bytes32 assertionId = umaOracle.assertTruth(
            claim,
            msg.sender, // asserter
            address(this), // callback recipient (contract settles)
            address(0), // no escalation manager
            DEFAULT_LIVENESS, // liveness
            dai, // currency
            ORACLE_BOND, // bond
            IDENTIFIER, // identifier
            0 // domain ID
        );

        evt.assertionId = assertionId;

        emit TruthAsserted(eventId, assertionId, proposedOutcome);
    }

    // Dispute assertion via UMA
    function disputeAssertion(uint256 eventId) external {
        Event storage evt = events[eventId];
        require(evt.assertionId != 0, "No assertion");
        umaOracle.disputeAssertion(evt.assertionId, msg.sender);
        emit AssertionDisputed(eventId, evt.assertionId);
    }

    // Settle event via UMA
    function settleEvent(uint256 eventId) external {
        Event storage evt = events[eventId];
        require(evt.assertionId != 0, "No assertion");
        require(!evt.resolved, "Already resolved");

        umaOracle.settleAssertion(evt.assertionId);
        OptimisticOracleV3Interface.Request memory request = umaOracle.getAssertion(evt.assertionId);
        int256 resolvedPrice = request.resolvedPrice;
        evt.outcome = (resolvedPrice == 1); // 1 for YES, 0 for NO
        evt.resolved = true;

        emit EventResolved(eventId, evt.outcome);
    }

    // Claim prize (winners)
    function claimPrize(uint256 eventId) external {
        Event storage evt = events[eventId];
        require(evt.resolved, "Not resolved");

        uint256 userUnits = evt.outcome ? userYesBets[eventId][msg.sender] : userNoBets[eventId][msg.sender];
        require(userUnits > 0, "No winning bets");

        uint256 prizePool = (evt.totalVolume * UNIT_PRICE * PRIZE_POOL_RATE) / 100;
        uint256 winningVolume = evt.outcome ? evt.yesVolume : evt.noVolume;
        uint256 share = (userUnits * prizePool) / winningVolume;

        if (evt.outcome) {
            userYesBets[eventId][msg.sender] = 0;
        } else {
            userNoBets[eventId][msg.sender] = 0;
        }

        dai.transfer(msg.sender, share);
        emit PrizeClaimed(eventId, msg.sender, share);
    }

    // Claim KOL share
    function claimKolShare(uint256 eventId, uint256 tokenId) external {
        Event storage evt = events[eventId];
        require(evt.resolved, "Not resolved");
        require(nft.ownerOf(tokenId) == msg.sender, "Not owner");

        uint256 totalRake = (evt.totalVolume * UNIT_PRICE * KOL_RATE) / 100;
        if (totalRake == 0) return;

        uint256 totalSampled = 0;
        uint256 myContribution = evt.sampledVolume[tokenId];
        if (tokenId == evt.initiatorTokenId) {
            myContribution *= 2; // Initiator x2
        }

        for (uint i = 0; i < evt.participatingTokenIds.length; i++) {
            uint256 pid = evt.participatingTokenIds[i];
            uint256 contrib = evt.sampledVolume[pid];
            if (pid == evt.initiatorTokenId) contrib *= 2;
            totalSampled += contrib;
        }

        if (totalSampled == 0) {
            // All to platform
            dai.transfer(owner(), totalRake);
        } else {
            uint256 share = (myContribution * totalRake) / totalSampled;
            dai.transfer(msg.sender, share);
            emit KolClaimed(eventId, tokenId, share);
        }
    }

    // Claim oracle reward (UMA handles deposit return via settle)
    function claimOracleReward(uint256 eventId) external {
        Event storage evt = events[eventId];
        require(evt.resolved, "Not resolved");

        uint256 oracleRake = (evt.totalVolume * UNIT_PRICE * ORACLE_RATE) / 100;
        // Assumer proposer claims from UMA separately; platform adds rake
        dai.transfer(evt.oracleProposer, oracleRake);
        emit OracleClaimed(eventId, evt.oracleProposer, oracleRake);
    }

    // Withdraw platform fees (accumulated)
    function withdrawPlatformFees(uint256 amount) external onlyOwner {
        dai.transfer(owner(), amount);
    }
}
