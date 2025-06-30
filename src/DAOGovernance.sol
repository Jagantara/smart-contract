// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract DAOGovernance {
    enum VoteType {
        Null,
        Yes,
        No
    }
    enum ClaimStatus {
        Pending,
        Approved,
        Rejected
    }

    struct ClaimProposal {
        address claimant;
        string reason;
        uint256 amount;
        uint256 createdAt;
        uint256 yesVotes;
        uint256 noVotes;
        ClaimStatus status;
        uint256 approvedAt;
        mapping(address => VoteType) votes;
    }

    IERC20 public jagaToken;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant THRESHOLD = 66; // 66% = 2/3

    uint256 public claimCounter;
    mapping(uint256 => ClaimProposal) private _claims;
    mapping(uint256 => address) public claimOwner;

    event ClaimSubmitted(
        uint256 indexed claimId,
        address indexed claimant,
        uint256 amount
    );
    event Voted(
        uint256 indexed claimId,
        address voter,
        bool approve,
        uint256 weight
    );
    event ClaimApproved(uint256 indexed claimId);
    event ClaimRejected(uint256 indexed claimId);

    constructor(address _jagaToken) {
        jagaToken = IERC20(_jagaToken);
    }

    modifier onlyClaimOwner(uint256 claimId) {
        require(_claims[claimId].claimant == msg.sender, "Not claimant");
        _;
    }

    function submitClaim(
        string calldata reason,
        uint256 amount
    ) external returns (uint256) {
        uint256 id = claimCounter++;

        ClaimProposal storage p = _claims[id];
        p.claimant = msg.sender;
        p.reason = reason;
        p.amount = amount;
        p.createdAt = block.timestamp;
        p.status = ClaimStatus.Pending;

        claimOwner[id] = msg.sender;

        emit ClaimSubmitted(id, msg.sender, amount);
        return id;
    }

    function vote(uint256 claimId, bool approve) external {
        ClaimProposal storage p = _claims[claimId];
        require(p.status == ClaimStatus.Pending, "Voting closed");
        require(
            block.timestamp <= p.createdAt + VOTING_PERIOD,
            "Voting expired"
        );

        VoteType prev = p.votes[msg.sender];
        require(prev == VoteType.Null, "Already voted");

        uint256 weight = jagaToken.balanceOf(msg.sender);
        require(weight > 0, "No voting power");

        if (approve) {
            p.yesVotes += weight;
            p.votes[msg.sender] = VoteType.Yes;
        } else {
            p.noVotes += weight;
            p.votes[msg.sender] = VoteType.No;
        }

        emit Voted(claimId, msg.sender, approve, weight);
    }

    function executeVote(uint256 claimId) external {
        ClaimProposal storage p = _claims[claimId];
        require(p.status == ClaimStatus.Pending, "Already executed");
        require(block.timestamp > p.createdAt, "Too early");

        uint256 totalVotes = p.yesVotes + p.noVotes;
        if (block.timestamp > p.createdAt + VOTING_PERIOD) {
            p.status = ClaimStatus.Rejected;
            emit ClaimRejected(claimId);
            return;
        }

        if (totalVotes == 0) revert("No participation");

        uint256 yesRatio = (p.yesVotes * 100) / totalVotes;
        if (yesRatio >= THRESHOLD) {
            p.status = ClaimStatus.Approved;
            p.approvedAt = block.timestamp;
            emit ClaimApproved(claimId);
        } else {
            p.status = ClaimStatus.Rejected;
            emit ClaimRejected(claimId);
        }
    }

    // ========== For ClaimManager.sol ==========

    function isClaimApproved(uint256 claimId) external view returns (bool) {
        return _claims[claimId].status == ClaimStatus.Approved;
    }

    function getClaimData(
        uint256 claimId
    ) external view returns (address, uint256, uint256) {
        ClaimProposal storage p = _claims[claimId];
        return (p.claimant, p.amount, p.approvedAt);
    }

    function getClaimStatus(
        uint256 claimId
    ) external view returns (ClaimStatus) {
        return _claims[claimId].status;
    }
}
