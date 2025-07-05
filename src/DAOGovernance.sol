// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IInsuranceManager {
    function isActive(address user) external view returns (bool);
    function policies(
        address user
    )
        external
        view
        returns (
            uint256 lastPaidAt,
            uint256 duration,
            address coveredAddress,
            uint256 tier,
            bool active
        );
}

/**
 * @title DAOGovernance
 * @notice DAO-based voting system for approving insurance claim proposals
 * @dev Token-weighted voting system using JagaToken with a 7-day voting period and 66% approval threshold
 */
contract DAOGovernance {
    // Types of votes a participant can cast
    enum VoteType {
        Null,
        Yes,
        No
    }

    // Status of the claim proposal
    enum ClaimStatus {
        Pending,
        Approved,
        Rejected
    }

    // Structure of a claim proposal
    struct ClaimProposal {
        address claimant;
        address coveredAddress;
        uint256 tier;
        string title;
        string reason;
        string claimType;
        uint256 amount;
        uint256 createdAt;
        uint256 yesVotes;
        uint256 noVotes;
        ClaimStatus status;
        uint256 approvedAt;
        mapping(address => VoteType) votes;
    }

    // JAGA token used for voting
    IERC20 public jagaToken;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public minimumVotingPeriod = 5 days;
    // 66% = 2/3 minimum threshold for approved claim
    uint256 public constant THRESHOLD = 66;
    address public insuranceManager;
    address public owner;

    // Counter for generating unique claim IDs
    uint256 public claimCounter;
    // Mapping of claim ID to ClaimProposal
    mapping(uint256 => ClaimProposal) public claims;
    // Mapping of claim ID to its claimant
    mapping(uint256 => address) public claimOwner;

    event ClaimSubmitted(
        uint256 indexed claimId,
        address indexed claimant,
        uint256 indexed amount
    );
    event ClaimDisplay(
        string indexed title,
        string indexed reason,
        string indexed claimType
    );
    event Voted(
        uint256 indexed claimId,
        address indexed voter,
        bool indexed approve,
        uint256 weight
    );
    event ClaimApproved(uint256 indexed claimId);
    event ClaimRejected(uint256 indexed claimId);

    /**
     * @notice Initializes the DAO governance contract
     */
    constructor(address _jagaToken, address _insuranceManager) {
        jagaToken = IERC20(_jagaToken);
        insuranceManager = _insuranceManager;
        owner = msg.sender;
    }

    modifier onlyClaimOwner(uint256 claimId) {
        require(claims[claimId].claimant == msg.sender, "Not claimant");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @notice Submits a new claim for DAO voting
     * @param reason Reason for the claim
     * @param title Title for the claim
     * @param claimType Claim Type for the claim
     * @param amount Requested payout amount
     * @return claimId The ID of the newly created claim
     */
    function submitClaim(
        string calldata reason,
        string calldata title,
        string calldata claimType,
        uint256 amount
    ) external returns (uint256) {
        require(
            IInsuranceManager(insuranceManager).isActive(msg.sender),
            "Invalid User"
        );
        (, , address coveredAddress, uint256 tier, ) = IInsuranceManager(
            insuranceManager
        ).policies(msg.sender);
        uint256 id = claimCounter++;

        ClaimProposal storage proposal = claims[id];
        proposal.claimant = msg.sender;
        proposal.coveredAddress = coveredAddress;
        proposal.tier = tier;
        proposal.title = title;
        proposal.reason = reason;
        proposal.claimType = claimType;
        proposal.amount = amount;
        proposal.createdAt = block.timestamp;
        proposal.status = ClaimStatus.Pending;

        claimOwner[id] = msg.sender;

        emit ClaimSubmitted(id, msg.sender, amount);
        emit ClaimDisplay(proposal.title, proposal.reason, proposal.claimType);
        return id;
    }

    /**
     * @notice Vote on a claim proposal using JagaToken weight
     * @param claimId The ID of the claim to vote on
     * @param approve Whether to vote yes (`true`) or no (`false`)
     */
    function vote(uint256 claimId, bool approve) external {
        ClaimProposal storage proposal = claims[claimId];
        require(proposal.status == ClaimStatus.Pending, "Voting closed");
        require(
            block.timestamp <= proposal.createdAt + VOTING_PERIOD,
            "Voting expired"
        );

        VoteType prev = proposal.votes[msg.sender];
        require(prev == VoteType.Null, "Already voted");

        uint256 weight = jagaToken.balanceOf(msg.sender);
        require(weight > 0, "No voting power");

        if (approve) {
            proposal.yesVotes += weight;
            proposal.votes[msg.sender] = VoteType.Yes;
        } else {
            proposal.noVotes += weight;
            proposal.votes[msg.sender] = VoteType.No;
        }

        emit Voted(claimId, msg.sender, approve, weight);
    }

    /**
     * @notice Executes the vote result after voting period or once quorum is met
     * @dev Proposal must be live for atleast 5 days for it to be executed
     * @param claimId The ID of the claim to finalize
     * @return yesRatio The ratio of approved votes to total votes
     */
    function executeVote(uint256 claimId) external returns (uint256 yesRatio) {
        ClaimProposal storage proposal = claims[claimId];
        require(proposal.status == ClaimStatus.Pending, "Already executed");

        uint256 totalVotes = proposal.yesVotes + proposal.noVotes;

        // checks if the proposal has been live for more than 5 days
        if (block.timestamp < proposal.createdAt + minimumVotingPeriod) {
            revert("Vote is allowed to be executed after 5 days");
        }

        // checks if the proposal has been live for less than 7 days
        if (block.timestamp > proposal.createdAt + VOTING_PERIOD) {
            proposal.status = ClaimStatus.Rejected;
            emit ClaimRejected(claimId);
            return 0;
        }
        if (totalVotes == 0) revert("No participation");

        // The ratio of approved votes to total votes
        yesRatio = (proposal.yesVotes * 100) / totalVotes;
        if (yesRatio >= THRESHOLD) {
            // Change the status to approved
            proposal.status = ClaimStatus.Approved;
            proposal.approvedAt = block.timestamp;
            emit ClaimApproved(claimId);
        } else {
            // Change the status to rejected
            proposal.status = ClaimStatus.Rejected;
            emit ClaimRejected(claimId);
        }
    }

    // ========== For ClaimManager.sol ==========

    function isClaimApproved(uint256 claimId) external view returns (bool) {
        return claims[claimId].status == ClaimStatus.Approved;
    }

    /**
     * @notice Get claim data needed for payout
     * @param claimId The ID of the claim
     * @return claimant Address of claimant
     * @return amount Amount requested
     * @return approvedAt Timestamp of approval
     */
    function getClaimData(
        uint256 claimId
    ) external view returns (address, uint256, uint256) {
        ClaimProposal storage proposal = claims[claimId];
        return (proposal.claimant, proposal.amount, proposal.approvedAt);
    }

    function getClaimStatus(
        uint256 claimId
    ) external view returns (ClaimStatus) {
        return claims[claimId].status;
    }

    /**
     * @notice Sets the configuration for Jaga token and insuranceManager contracts.
     * @dev Only callable by the contract owner.
     * @param _jagaToken The address of the Jaga token contract.
     * @param _insuranceManager The address of the insuranceManager contract.
     */
    function setConfig(
        address _jagaToken,
        address _insuranceManager
    ) external onlyOwner {
        jagaToken = IERC20(_jagaToken);
        insuranceManager = _insuranceManager;
    }

    function setMinimumVotingPeriod(
        uint256 _minimumVotingPeriod
    ) public onlyOwner {
        minimumVotingPeriod = _minimumVotingPeriod;
    }
}
