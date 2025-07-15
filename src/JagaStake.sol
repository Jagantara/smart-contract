// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {JagaToken} from "./JagaToken.sol";

interface IJagaToken {
    function mint(address _to, uint256 _amount) external;
    function burn(address _to, uint256 _amount) external;
}

/**
 * @title JagaStake - Synthetix Style
 * @notice A staking contract using Synthetix-style continuous rewards distribution
 * @dev Rewards are distributed continuously based on time-weighted stake participation
 */
contract JagaStake {
    IERC20 public immutable usdc;
    JagaToken public jagaToken;
    address public insuranceManager;
    address public claimManager;
    address public owner;

    uint256 public totalSupply; // Total staked tokens
    uint256 public rewardRate; // Reward rate per second
    uint256 public lastUpdateTime; // Last time rewards were updated
    uint256 public rewardPerTokenStored; // Reward per token stored (accumulated)
    uint256 public rewardsDuration = 30 days; // Duration for reward distribution (default 30 days)
    uint256 public periodFinish; // Timestamp when current reward period ends
    mapping(address => uint256) public balances; // User balances
    mapping(address => uint256) public userRewardPerTokenPaid; // User reward per token paid (last claimed rewardPerToken)
    mapping(address => uint256) public rewards; // User rewards to be claimed

    // Track all stakers
    address[] public stakers;
    mapping(address => bool) public isStaker;

    event Staked(address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount);
    event RewardPaid(address indexed user, uint256 indexed reward);
    event RewardAdded(uint256 indexed reward);
    event RewardsDurationUpdated(uint256 indexed newDuration);

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
        jagaToken = new JagaToken();
        owner = msg.sender;
        lastUpdateTime = block.timestamp;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /**
     * @notice Returns the last timestamp at which rewards were applicable
     * @return Timestamp (in seconds)
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @notice Returns the accumulated reward per token.
     * @return Reward per token scaled by 1e6.
     */
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) *
                rewardRate *
                1e6) / totalSupply);
    }

    /**
     * @notice Returns the earned rewards for a specific user.
     * @param account The address of the user.
     * @return The amount of USDC reward earned by the user.
     */
    function earned(address account) public view returns (uint256) {
        return
            (balances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) /
            1e6 +
            rewards[account];
    }

    /**
     * @notice Stakes USDC and mints JagaToken to the staker.
     * @dev calls updateReward(msg.sender) which updates the global state and user's reward
     * @param amount The amount of USDC to stake.
     */
    function stake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");

        // Add user to stakers list if not already present
        if (!isStaker[msg.sender]) {
            stakers.push(msg.sender);
            isStaker[msg.sender] = true;
        }

        // Update balances
        totalSupply += amount;
        balances[msg.sender] += amount;

        // Transfer USDC and mint JagaToken
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        IJagaToken(address(jagaToken)).mint(msg.sender, amount);

        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Unstakes USDC and burns the equivalent JagaToken.
     * @dev calls updateReward(msg.sender) which updates the global state and user's reward
     * @param amount The amount of USDC to unstake.
     */
    function unstake(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot unstake 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        // Update balances
        totalSupply -= amount;
        balances[msg.sender] -= amount;

        // Remove from stakers list if no more stake
        if (balances[msg.sender] == 0) {
            isStaker[msg.sender] = false;
        }

        // Transfer USDC and burn JagaToken
        require(usdc.transfer(msg.sender, amount), "Transfer failed");
        IJagaToken(address(jagaToken)).burn(msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Claims all pending rewards for the caller.
     * @dev calls updateReward(msg.sender) which updates the global state and user's reward
     */
    function claim() external updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            require(
                usdc.transfer(msg.sender, reward),
                "Reward transfer failed"
            );
            emit RewardPaid(msg.sender, reward);
        }
    }

    /**
     * @notice Adds rewards to be distributed over the rewards duration
     * @dev Only the insuranceManager can call this; calls updateReward(address(0))
     * @param reward Amount of rewards to add
     */
    function notifyRewardAmount(
        uint256 reward
    ) external updateReward(address(0)) {
        require(msg.sender == insuranceManager, "Only insurance manager");

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardsDuration;
        }

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        // Transfer rewards to contract
        require(
            usdc.transferFrom(msg.sender, address(this), reward),
            "Transfer failed"
        );

        emit RewardAdded(reward);
    }

    /**
     * @notice Updates the rewards duration
     * @dev Only callable by the owner
     * @param _rewardsDuration New duration in seconds
     */
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    /**
     * @notice Emergency withdraw for ClaimManager to handle claim payouts
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external {
        require(msg.sender == claimManager, "Invalid user");
        require(usdc.transfer(msg.sender, amount), "Transfer failed");
    }

    /**
     * @notice Sets the configuration for InsuranceManager and ClaimManager contracts
     * @dev Only callable by the owner
     * @param _insuranceManager The address of the InsuranceManager contract
     * @param _claimManager The address of the ClaimManager contract
     */
    function setConfig(
        address _insuranceManager,
        address _claimManager
    ) external onlyOwner {
        insuranceManager = _insuranceManager;
        claimManager = _claimManager;
    }

    /**
     * @notice Returns the JagaToken contract
     * @return The JagaToken contract instance.
     */
    function getJagaToken() external view returns (JagaToken) {
        return jagaToken;
    }

    /**
     * @notice Returns all stakers
     * @return Array of staker addresses.
     */
    function getStakers() external view returns (address[] memory) {
        return stakers;
    }

    /**
     * @notice Returns the number of stakers
     * @return The total number of stakers.
     */
    function getStakersCount() external view returns (uint256) {
        return stakers.length;
    }

    /**
     * @notice Returns the balance of a user
     * @return Amount of USDC staked.
     */
    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    /**
     * @notice Returns the time left in the current reward period
     * @return Time left in seconds
     */
    function timeLeft() external view returns (uint256) {
        if (block.timestamp >= periodFinish) {
            return 0;
        }
        return periodFinish - block.timestamp;
    }
}
