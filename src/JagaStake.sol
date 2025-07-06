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

    // User's current staked USDC amount
    mapping(address => uint256) public currentStake;
    // Mapping from session ID to session data
    mapping(uint256 => Session) public sessions;
    // Mapping of user stake per session (sessionId => user => staked amount)
    mapping(uint256 => mapping(address => uint256)) public sessionStake;
    // Mapping of user has claimed reward per session (sessionId => user => reward claimed)
    mapping(uint256 => mapping(address => bool)) public claimed;
    mapping(address => uint256[]) public sessionToClaim;

    // Track all stakers
    address[] public stakers;
    mapping(address => bool) public isStaker;

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

    /// @dev Updates session counter and creates next sessions if the previous session has passed
    modifier updateSession() {
        uint256 elapsed = block.timestamp - sessionStart;

        if (elapsed >= sessionDuration) {
            uint256 sessionsPassed = elapsed / sessionDuration;

            // Process each session that has passed
            for (uint256 i = 0; i < sessionsPassed; i++) {
                uint256 newSessionId = sessionCounter + 1;

                // Calculate total staked for the new session
                uint256 totalStaked = 0;

                // For each staker that has a current stake, copy it to the new session
                for (uint256 k = 0; k < stakers.length; k++) {
                    address staker = stakers[k];
                    if (currentStake[staker] > 0) {
                        sessionStake[newSessionId][staker] = currentStake[
                            staker
                        ];
                        totalStaked += currentStake[staker];

                        // Add to claim list if not already present
                        bool alreadyAdded = false;
                        for (
                            uint256 j = 0;
                            j < sessionToClaim[staker].length;
                            j++
                        ) {
                            if (sessionToClaim[staker][j] == newSessionId) {
                                alreadyAdded = true;
                                break;
                            }
                        }
                        if (!alreadyAdded) {
                            sessionToClaim[staker].push(newSessionId);
                        }
                    }
                }

                // Set the calculated total staked
                sessions[newSessionId].totalStaked = totalStaked;
                sessionCounter = newSessionId;
            }

            sessionStart += sessionsPassed * sessionDuration;
        }
        _;
    }

    /**
     * @notice Stakes USDC for the next session and mints JagaToken
     * @param amount The amount of USDC to stake
     */
    function stake(uint256 amount) external updateSession {
        require(amount > 0, "Zero stake");

        // Add user to stakers list if not already present
        if (!isStaker[msg.sender]) {
            stakers.push(msg.sender);
            isStaker[msg.sender] = true;
        }

        // update state
        currentStake[msg.sender] += amount;
        // only able to stake the next session
        sessions[sessionCounter + 1].totalStaked += amount;
        if (sessionStake[sessionCounter + 1][msg.sender] == 0) {
            sessionToClaim[msg.sender].push(sessionCounter + 1);
        }
        sessionStake[sessionCounter + 1][msg.sender] += amount;

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

        // Remove from sessionToClaim if stake becomes 0
        if (sessionStake[sessionCounter + 1][msg.sender] == 0) {
            // Find and remove the session from sessionToClaim
            for (uint256 i = 0; i < sessionToClaim[msg.sender].length; i++) {
                if (sessionToClaim[msg.sender][i] == sessionCounter + 1) {
                    // Move the last element to this position and pop
                    sessionToClaim[msg.sender][i] = sessionToClaim[msg.sender][
                        sessionToClaim[msg.sender].length - 1
                    ];
                    sessionToClaim[msg.sender].pop();
                    break;
                }
            }
        }

        // Remove from stakers list if no more stake
        if (currentStake[msg.sender] == 0) {
            isStaker[msg.sender] = false;
        }

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

        // transfer the revenue from insuranceManager to this contract for specific sessionId
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
                continue;
            }

            if (
                sessions[sessionId].totalReward == 0 ||
                claimed[sessionId][msg.sender] ||
                sessionStake[sessionId][msg.sender] == 0
            ) {
                continue; // Skip this session
            }

            totalReward +=
                (sessionStake[sessionId][msg.sender] *
                    sessions[sessionId].totalReward) /
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
    function pendingReward()
        public
        updateSession
        returns (uint256 totalReward)
    {
        for (uint256 i = 0; i < sessionToClaim[msg.sender].length; i++) {
            uint256 sessionId = sessionToClaim[msg.sender][i];
            if (!sessions[sessionId].finalized) {
                continue; // Skip this session
            }

            if (
                sessions[sessionId].totalReward == 0 ||
                claimed[sessionId][msg.sender] ||
                sessionStake[sessionId][msg.sender] == 0 ||
                sessions[sessionId].totalStaked == 0
            ) {
                continue; // Skip this session
            }

            totalReward +=
                (sessionStake[sessionId][msg.sender] *
                    sessions[sessionId].totalReward) /
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

    // Additional getter functions for debugging
    function getStakers() external view returns (address[] memory) {
        return stakers;
    }

    function getStakersCount() external view returns (uint256) {
        return stakers.length;
    }
}
