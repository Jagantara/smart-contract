// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IClaimManager {
    function receiveRevenue(uint256 amount) external;
}

import {IJagaStake} from "./interfaces/IJagaStake.sol";

/**
 * @title InsuranceManager
 * @notice This contract manages user insurance subscriptions (policy premium payments) and distributes collected premiums to various modules (staking, claims, investment, owner).
 * @dev Users pay a fixed premium in USDC and the contract periodically distributes collected funds.
 */
contract InsuranceManager {
    address public owner;
    address public jagaStakeContract;
    address public claimManagerContract;
    address public morphoReinvestContract;
    // Duration for which a premium remains valid
    uint256 public premiumDuration;
    uint256 public totalUser;

    IERC20 public usdc;

    struct Policy {
        uint256 lastPaidAt;
        uint256 duration;
        address coveredAddress;
        uint256 tier;
        bool active;
        uint256 amountToCover;
    }

    mapping(address => Policy) public policies;

    mapping(uint256 => uint256) public tierToPercentage;

    uint256 public totalCollected;

    event PremiumPaid(address indexed user, uint256 indexed amount);
    event RevenueTransferred(uint256 indexed amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        address _usdc,
        uint256 _percentage1,
        uint256 _percentage2,
        uint256 _percentage3,
        uint256 _premiumDuration
    ) {
        owner = msg.sender;
        usdc = IERC20(_usdc);
        tierToPercentage[1] = _percentage1; // 10 (0.1%)
        tierToPercentage[2] = _percentage2; // 30 (0.3%)
        tierToPercentage[3] = _percentage3; // 50 (0.5%)
        premiumDuration = _premiumDuration;
    }

    /**
     * @notice Allows a user to pay their insurance premium based on the duration
     * @dev Transfers USDC from the user to the contract, marks their policy as active
     * @param tier The tier of insurance activation
     * @param duration The duration amount of insurance activation
     * @param coveredAddress The covered address of insurance activation
     */
    function payPremium(
        uint256 tier,
        uint256 duration,
        address coveredAddress,
        uint256 amountToCover
    ) external {
        require(tierToPercentage[tier] != 0, "Tier is invalid");
        uint256 premiumPrice = (amountToCover * tierToPercentage[tier]) /
            100000;

        // update the policy state
        policies[msg.sender].lastPaidAt = block.timestamp;
        policies[msg.sender].active = true;
        policies[msg.sender].duration = duration;
        policies[msg.sender].coveredAddress = coveredAddress;
        policies[msg.sender].tier = tier;
        policies[msg.sender].amountToCover = amountToCover;
        totalCollected += premiumPrice;
        if (policies[msg.sender].lastPaidAt == 0) {
            totalUser += 1;
        }

        uint256 price = premiumPrice * duration;
        require(
            usdc.transferFrom(msg.sender, address(this), price),
            "Transfer failed"
        );

        emit PremiumPaid(msg.sender, premiumPrice);
    }

    /**
     * @notice Checks if a user's policy is currently active
     * @param user The address of the user to check
     * @return True if the policy is active and not expired, false otherwise
     */
    function isActive(address user) external view returns (bool) {
        Policy memory p = policies[user];
        return
            p.active &&
            block.timestamp <= p.lastPaidAt + (premiumDuration * p.duration);
    }

    /**
     * @notice Distributes collected revenue to other modules (JagaStake, ClaimManager, InvestmentManager)
     * @dev Only callable by the owner. Allocation: 30% to staking, 25% to claims, 20% to owner, 25% to investment
     * @param balance The amount of money that's want to be revenued
     */
    function transferRevenue(uint256 balance) external onlyOwner {
        uint256 balanceManager = usdc.balanceOf(address(this));
        require(balanceManager >= balance, "No revenue");

        // set allocation based on balance
        uint256 jagaStakeAllocation = (30 * balance) / 100;
        uint256 ownerAllocation = (20 * balance) / 100;
        uint256 claimManagerAllocation = (25 * balance) / 100;
        uint256 morphoReinvestAllocation = balance -
            (jagaStakeAllocation + ownerAllocation + claimManagerAllocation);

        IJagaStake(jagaStakeContract).notifyRewardAmount(jagaStakeAllocation);
        usdc.transfer(address(owner), ownerAllocation);
        usdc.transfer(address(claimManagerContract), claimManagerAllocation);
        usdc.transfer(
            address(morphoReinvestContract),
            morphoReinvestAllocation
        );

        emit RevenueTransferred(balance);
    }

    function setApproval(uint256 amount) external onlyOwner {
        usdc.approve(address(jagaStakeContract), amount);
    }

    function getPriceFromAmountTier(
        uint256 amountToCover,
        uint256 tier
    ) external view returns (uint256) {
        return (amountToCover * tierToPercentage[tier]) / 100000;
    }

    /**
     * @notice Sets the configuration for JagaStake, ClaimManager and MorphoReinvest contracts.
     * @dev Only callable by the contract owner.
     * @param _jagaStake The address of the Jaga stake contract.
     * @param _morphoReinvest The address of the MorphoReinvest contract.
     */
    function setConfig(
        address _jagaStake,
        address _claimManager,
        address _morphoReinvest
    ) external onlyOwner {
        jagaStakeContract = _jagaStake;
        claimManagerContract = _claimManager;
        morphoReinvestContract = _morphoReinvest;
    }
}
