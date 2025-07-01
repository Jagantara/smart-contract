// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IClaimManager {
    function receiveRevenue(uint256 amount) external;
}

interface IJagaStake {
    function addRevenue(uint256 sessionId, uint256 amount) external;
}

/**
 * @title InsuranceManager
 * @notice This contract manages user insurance subscriptions (policy premium payments) and distributes collected premiums to various modules (staking, claims, investment, owner).
 * @dev Users pay a fixed premium in USDC and the contract periodically distributes collected funds.
 */
contract InsuranceManager {
    address public owner;
    address public jagaStakeContract;
    address public claimManagerContract;
    address public investmentManagerContract;
    // Price of a premium payment in USDC
    uint256 public premiumPrice;
    // Duration for which a premium remains valid
    uint256 public premiumDuration;

    IERC20 public usdc;

    struct Policy {
        uint256 lastPaidAt;
        bool active;
    }

    mapping(address => Policy) public policies;

    uint256 public totalCollected;

    event PremiumPaid(address indexed user, uint256 indexed amount);
    event RevenueTransferred(uint256 indexed amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        address _usdc,
        uint256 _premiumPrice,
        uint256 _premiumDuration
    ) {
        owner = msg.sender;
        usdc = IERC20(_usdc);
        premiumPrice = _premiumPrice;
        premiumDuration = _premiumDuration;
    }

    /**
     * @notice Allows a user to pay their insurance premium
     * @dev Transfers USDC from the user to the contract, marks their policy as active
     */
    function payPremium() external {
        require(
            usdc.transferFrom(msg.sender, address(this), premiumPrice),
            "Transfer failed"
        );

        policies[msg.sender].lastPaidAt = block.timestamp;
        policies[msg.sender].active = true;
        totalCollected += premiumPrice;

        emit PremiumPaid(msg.sender, premiumPrice);
    }

    function isActive(address user) external view returns (bool) {
        Policy memory p = policies[user];
        return p.active && block.timestamp <= p.lastPaidAt + premiumDuration;
    }

    /**
     * @notice Distributes collected revenue to other modules (JagaStake, ClaimManager, InvestmentManager)
     * @dev Only callable by the owner. Allocation: 30% to staking, 25% to claims, 20% to owner, 25% to investment
     * @param sessionId The session ID used in JagaStake when adding revenue
     */
    function transferRevenue(uint256 sessionId) external onlyOwner {
        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, "No revenue");

        // set allocation based on balance
        uint256 jagaStakeAllocation = (30 * balance) / 100;
        uint256 ownerAllocation = (20 * balance) / 100;
        uint256 claimManagerAllocation = (25 * balance) / 100;

        IJagaStake(jagaStakeContract).addRevenue(
            sessionId,
            jagaStakeAllocation
        );
        usdc.transfer(address(owner), ownerAllocation);
        usdc.transfer(address(claimManagerContract), claimManagerAllocation);
        // last transfer use balance left to avoid any precision loss from the calculation
        usdc.transfer(address(investmentManagerContract), balance);

        emit RevenueTransferred(balance);
    }

    /**
     * @notice Sets the configuration for JagaStake, ClaimManager and InvestmentManager contracts.
     * @dev Only callable by the contract owner.
     * @param _jagaStake The address of the Jaga stake contract.
     * @param _investmentManager The address of the InvestmentManager contract.
     */
    function setConfig(
        address _jagaStake,
        address _claimManager,
        address _investmentManager
    ) external onlyOwner {
        jagaStakeContract = _jagaStake;
        claimManagerContract = _claimManager;
        investmentManagerContract = _investmentManager;
    }
}
