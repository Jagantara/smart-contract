// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract JagaStake {
    IERC20 public immutable usdc;
    uint256 public constant SESSION_DURATION = 30 days;

    struct Session {
        uint256 totalStaked;
        uint256 totalReward;
        bool finalized;
    }

    uint256 public sessionCounter; // current session index
    uint256 public sessionStart; // timestamp of current session start

    mapping(uint256 => Session) public sessions; // sessionId => session info
    mapping(address => uint256) public userStake; // active amount (across sessions)
    mapping(address => bool) public isActive; // is staker currently active
    mapping(uint256 => mapping(address => bool)) public assignedToSession;
    mapping(uint256 => mapping(address => bool)) public claimedReward;

    event Assigned(address indexed user, uint256 session);
    event RevenueAdded(uint256 session, uint256 amount);
    event Claimed(address indexed user, uint256 session, uint256 reward);
    event Unstaked(address indexed user, uint256 amount);

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
        sessionStart = block.timestamp;
    }

    modifier updateSession() {
        uint256 nowTime = block.timestamp;
        uint256 elapsed = nowTime - sessionStart;
        uint256 nextSession = sessionCounter;

        if (elapsed >= SESSION_DURATION) {
            uint256 sessionAdvance = elapsed / SESSION_DURATION;
            nextSession += sessionAdvance;
            sessionStart += sessionAdvance * SESSION_DURATION;
            sessionCounter = nextSession;
        }

        _;
    }

    // Assign yourself to upcoming session before it starts
    function assignToNextSession(uint256 amount) external updateSession {
        require(amount > 0, "Zero amount");
        require(
            !assignedToSession[sessionCounter + 1][msg.sender],
            "Already assigned"
        );

        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        userStake[msg.sender] += amount;
        isActive[msg.sender] = true;

        uint256 targetSession = sessionCounter + 1;
        assignedToSession[targetSession][msg.sender] = true;
        sessions[targetSession].totalStaked += amount;

        emit Assigned(msg.sender, targetSession);
    }

    function addRevenue(uint256 sessionId, uint256 amount) external {
        require(sessionId < sessionCounter, "Can only reward past sessions");
        require(!sessions[sessionId].finalized, "Already finalized");

        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        sessions[sessionId].totalReward += amount;
        sessions[sessionId].finalized = true;

        emit RevenueAdded(sessionId, amount);
    }

    function claim(uint256 sessionId) external {
        require(assignedToSession[sessionId][msg.sender], "Not assigned");
        require(!claimedReward[sessionId][msg.sender], "Already claimed");
        require(sessions[sessionId].finalized, "Not finalized");

        uint256 stake = userStake[msg.sender];
        uint256 reward = (stake * sessions[sessionId].totalReward) /
            sessions[sessionId].totalStaked;

        claimedReward[sessionId][msg.sender] = true;
        require(usdc.transfer(msg.sender, reward), "Claim failed");

        emit Claimed(msg.sender, sessionId, reward);
    }

    function unstake() external {
        require(isActive[msg.sender], "Not active");
        uint256 amount = userStake[msg.sender];

        isActive[msg.sender] = false;
        userStake[msg.sender] = 0;

        require(usdc.transfer(msg.sender, amount), "Unstake failed");
        emit Unstaked(msg.sender, amount);
    }

    // Helpers
    function currentSession() external view returns (uint256) {
        return sessionCounter;
    }

    function nextSessionStart() external view returns (uint256) {
        return sessionStart + SESSION_DURATION;
    }

    function isAssigned(
        address user,
        uint256 sessionId
    ) external view returns (bool) {
        return assignedToSession[sessionId][user];
    }

    function pendingReward(
        address user,
        uint256 sessionId
    ) external view returns (uint256) {
        if (
            !assignedToSession[sessionId][user] ||
            claimedReward[sessionId][user] ||
            !sessions[sessionId].finalized
        ) {
            return 0;
        }

        return
            (userStake[user] * sessions[sessionId].totalReward) /
            sessions[sessionId].totalStaked;
    }
}
