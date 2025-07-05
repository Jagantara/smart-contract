// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {JagaToken} from "./JagaToken.sol";

interface IJagaToken {
    function mint(address _to, uint256 _amount) external;
    function burn(address _to, uint256 _amount) external;
}

/**
 * @title JagaStake
 * @notice A staking contract where users stake USDC to earn rewards per 30-day session
 * @dev Rewards are distributed proportionally based on stake in finalized sessions
 */
contract JagaStake {
    IERC20 public immutable usdc;
    uint256 public sessionDuration = 30 days;
    address public insuranceManager;
    JagaToken public jagaToken;
    // Address authorized to call emergency withdrawals (e.g. ClaimManager)
    address public claimManager;
    address public owner;
    // Index of the current staking session
    uint256 public sessionCounter;
    // Timestamp of the current session start
    uint256 public sessionStart;

    // Structure of session data
    struct Session {
        uint256 totalStaked;
        uint256 totalReward;
        bool finalized;
    }

    // User’s current staked USDC amount
    mapping(address => uint256) public currentStake;
    // Mapping from session ID to session data
    mapping(uint256 => Session) public sessions;
    // Mapping of user stake per session (sessionId => user => staked amount)
    mapping(uint256 => mapping(address => uint256)) public sessionStake;
    // Mapping of user has claimed reward per session (sessionId => user => reward claimed)
    mapping(uint256 => mapping(address => bool)) public claimed;
    mapping(address => uint256[]) public sessionToClaim;

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

    /// @dev Updates session counter and creates next sessions if the previos session has passed
    modifier updateSession() {
        uint256 elapsed = block.timestamp - sessionStart;

        if (elapsed >= sessionDuration) {
            uint256 sessionsPassed = elapsed / sessionDuration;

            sessionStart += sessionsPassed * sessionDuration;
            sessionCounter += sessionsPassed;
        }

        _;
    }

    /**
     * @notice Stakes USDC for the next session and mints JagaToken
     * @param amount The amount of USDC to stake
     */
    function stake(uint256 amount) external updateSession {
        require(amount > 0, "Zero stake");

        // update state
        currentStake[msg.sender] += amount;
        // only able to stake the next session
        sessions[sessionCounter + 1].totalStaked += amount;
        sessionStake[sessionCounter + 1][msg.sender] += amount;
        sessionToClaim[msg.sender].push(sessionCounter + 1);

        // user stake their money and the JagaToken minted
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        IJagaToken(address(jagaToken)).mint(msg.sender, amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstakes USDC from the current session
     * @param amount Amount of USDC to unstake
     */
    function unstake(uint256 amount) external updateSession {
        require(currentStake[msg.sender] >= amount, "Insufficient stake");

        // update state
        currentStake[msg.sender] -= amount;
        sessions[sessionCounter + 1].totalStaked -= amount;
        sessionStake[sessionCounter + 1][msg.sender] -= amount;
        sessionToClaim[msg.sender].pop();

        // user received their staked money and the JagaToken burned
        require(usdc.transfer(msg.sender, amount), "Transfer failed");
        IJagaToken(address(jagaToken)).burn(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Adds revenue to a finalized past session
     * @dev Only the insuranceManager can call this
     * @param sessionId ID of the session to reward
     * @param amount Revenue amount to add
     */
    function addRevenue(
        uint256 sessionId,
        uint256 amount
    ) external updateSession {
        require(msg.sender == insuranceManager, "You're not allowed!");
        require(sessionId < sessionCounter, "Can only reward past sessions");
        require(!sessions[sessionId].finalized, "Already finalized");

        // update state
        sessions[sessionId].totalReward += amount;
        sessions[sessionId].finalized = true;

        // transfer the revenue from insuranceManager to this contract for spesific sessionId
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        emit RevenueAdded(sessionId, amount);
    }

    /**
     * @notice Claims staking reward for a given session
     */
    function claim() external updateSession {
        uint256 totalReward;

        for (uint256 i = 0; i < sessionToClaim[msg.sender].length; i++) {
            uint256 sessionId = sessionToClaim[msg.sender][i];
            if (!sessions[sessionId].finalized) {
                break;
            }
            require(
                sessions[sessionId].totalReward > 0,
                "There are no revenue to be shared"
            );
            require(!claimed[sessionId][msg.sender], "Already claimed");

            uint256 sessionStaked = sessionStake[sessionId][msg.sender];
            require(sessionStaked > 0, "No stake");

            totalReward +=
                (sessionStaked * sessions[sessionId].totalReward) /
                sessions[sessionId].totalStaked;
            claimed[sessionId][msg.sender] = true;
            emit Claimed(msg.sender, sessionId, totalReward);
        }
        delete sessionToClaim[msg.sender];

        require(usdc.transfer(msg.sender, totalReward), "Claim failed");
    }

    /**
     * @notice Returns the current session number
     * @dev Automatically updates session if needed
     */
    function currentSession() external updateSession returns (uint256) {
        return sessionCounter;
    }

    /**
     * @notice Returns the start timestamp of the next session
     * @dev Automatically updates session if needed
     */
    function nextSessionStart() external updateSession returns (uint256) {
        return sessionStart + sessionDuration;
    }

    /**
     * @notice Returns the time left until the next session starts
     * @dev Automatically updates session if needed
     */
    function timeLeft() external updateSession returns (uint256) {
        uint256 elapsed = block.timestamp - sessionStart;
        if (elapsed >= sessionDuration) {
            return 0;
        }
        return sessionDuration - elapsed;
    }

    function getJagaToken() external view returns (JagaToken) {
        return jagaToken;
    }

    /**
     * @notice Returns the pending reward for a user in a session (getter function for frontend)
     * @return totalReward The pending reward amount
     */
    function pendingReward() public view returns (uint256 totalReward) {
        for (uint256 i = 0; i < sessionToClaim[msg.sender].length; i++) {
            uint256 sessionId = sessionToClaim[msg.sender][i];
            if (!sessions[sessionId].finalized) {
                break;
            }
            require(
                sessions[sessionId].totalReward > 0,
                "There are no revenue to be shared"
            );
            require(!claimed[sessionId][msg.sender], "Already claimed");

            uint256 sessionStaked = sessionStake[sessionId][msg.sender];
            require(sessionStaked > 0, "No stake");

            totalReward +=
                (sessionStaked * sessions[sessionId].totalReward) /
                sessions[sessionId].totalStaked;
        }
    }

    /**
     * @notice Emergency withdraw for ClaimManager to handle claim payouts
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external {
        require(msg.sender == claimManager, "Invalid user");
        IERC20(usdc).transfer(msg.sender, amount);
    }

    /**
     * @notice Sets the configuration for InsuranceManager and ClaimManager contracts.
     * @dev Only callable by the contract owner.
     * @param _insuranceManager The address of the InsuranceManager contract.
     * @param _claimManager The address of the ClaimManager contract.
     */
    function setConfig(
        address _insuranceManager,
        address _claimManager
    ) external onlyOwner {
        insuranceManager = _insuranceManager;
        claimManager = _claimManager;
    }

    function setSessionDuration(uint256 _sessionDuration) public onlyOwner {
        sessionDuration = _sessionDuration;
    }
}
