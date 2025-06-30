// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {JagaToken} from "./JagaToken.sol";

interface IJagaToken {
    function mint(address _to, uint256 _amount) external;
    function burn(address _to, uint256 _amount) external;
}

contract JagaStake {
    IERC20 public immutable usdc;
    uint256 public constant SESSION_DURATION = 30 days;
    address public insuranceManager;
    JagaToken public jagaToken;
    address public claimManager;
    address public owner;
    uint256 public sessionCounter; // current session number
    uint256 public sessionStart; // timestamp of current session start

    struct Session {
        uint256 totalStaked;
        uint256 totalReward;
        bool finalized;
    }

    mapping(address => uint256) public currentStake;
    mapping(uint256 => Session) public sessions;
    mapping(uint256 => mapping(address => uint256)) public sessionStake;
    mapping(uint256 => mapping(address => bool)) public claimed;

    event Staked(address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount);
    event Claimed(
        address indexed user,
        uint256 indexed session,
        uint256 indexed reward
    );
    event RevenueAdded(uint256 indexed session, uint256 indexed amount);

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
        sessionStart = block.timestamp;
        sessionCounter = 0;
        jagaToken = new JagaToken();
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier updateSession() {
        uint256 elapsed = block.timestamp - sessionStart;

        if (elapsed >= SESSION_DURATION) {
            uint256 sessionsPassed = elapsed / SESSION_DURATION;

            for (uint256 i = 1; i <= sessionsPassed; i++) {
                uint256 newSession = sessionCounter + i;
                sessions[newSession].totalStaked = sessions[sessionCounter]
                    .totalStaked;
            }

            sessionStart += sessionsPassed * SESSION_DURATION;
            sessionCounter += sessionsPassed;
        }

        _;
    }

    function stake(uint256 amount) external updateSession {
        require(amount > 0, "Zero stake");

        currentStake[msg.sender] += amount;
        // only able to stake the next session
        sessions[sessionCounter + 1].totalStaked += amount;
        sessionStake[sessionCounter + 1][msg.sender] += amount;

        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        IJagaToken(address(jagaToken)).mint(msg.sender, amount);

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external updateSession {
        require(currentStake[msg.sender] >= amount, "Insufficient stake");

        currentStake[msg.sender] -= amount;
        sessions[sessionCounter].totalStaked -= amount;
        sessionStake[sessionCounter][msg.sender] -= amount;

        require(usdc.transfer(msg.sender, amount), "Transfer failed");
        IJagaToken(address(jagaToken)).mint(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    function addRevenue(uint256 sessionId, uint256 amount) external {
        require(msg.sender == insuranceManager, "You're not allowed!");
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

    function claim(uint256 sessionId) external updateSession {
        require(
            sessions[sessionId].totalReward > 0,
            "There are no revenue to be shared"
        );
        require(sessions[sessionId].finalized, "Not finalized");
        require(!claimed[sessionId][msg.sender], "Already claimed");

        uint256 sessionStaked = sessionStake[sessionId][msg.sender];
        require(sessionStaked > 0, "No stake");

        uint256 total = sessions[sessionId].totalStaked;
        uint256 reward = (sessionStaked * sessions[sessionId].totalReward) /
            total;

        claimed[sessionId][msg.sender] = true;

        require(usdc.transfer(msg.sender, reward), "Claim failed");
        emit Claimed(msg.sender, sessionId, reward);
    }

    // Optional views
    function currentSession() external view returns (uint256) {
        return sessionCounter;
    }

    function nextSessionStart() external view returns (uint256) {
        return sessionStart + SESSION_DURATION;
    }

    function timeLeft() external view updateSession returns (uint256) {
        return SESSION_DURATION - (sessionStart + block.timestamp);
    }

    function getJagaToken() external view returns (address) {
        return address(jagaToken);
    }

    function pendingReward(
        address user,
        uint256 sessionId
    ) external view returns (uint256) {
        if (claimed[sessionId][user] || !sessions[sessionId].finalized) {
            return 0;
        }

        uint256 userShare = sessionStake[sessionId][user];
        if (userShare == 0) return 0;

        uint256 reward = (userShare * sessions[sessionId].totalReward) /
            sessions[sessionId].totalStaked;
        return reward;
    }

    function withdraw(uint256 amount) external {
        require(msg.sender == claimManager, "Invalid user");
        IERC20(usdc).transfer(msg.sender, amount);
    }

    function setConfig(
        address _insuranceManager,
        address _claimManager
    ) external onlyOwner {
        insuranceManager = _insuranceManager;
        claimManager = _claimManager;
    }
}
