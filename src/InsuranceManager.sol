// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IClaimManager {
    function receiveRevenue(uint256 amount) external;
}

interface IJagaStake {
    function addRevenue(uint256 sessionId, uint256 amount) external;
}

contract InsuranceManager {
    address public owner;
    address public jagaStakeContract;
    address public claimManagerContract;
    address public investmentManagerContract;
    uint256 public premiumPrice;
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

    function transferRevenue(uint256 sessionId) external onlyOwner {
        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, "No revenue");

        uint256 jagaStakeAllocation = (30 * balance) / 100;
        uint256 ownerAllocation = (20 * balance) / 100;
        uint256 claimManagerAllocation = (25 * balance) / 100;

        IJagaStake(jagaStakeContract).addRevenue(
            sessionId,
            jagaStakeAllocation
        );
        usdc.transfer(address(owner), ownerAllocation);
        usdc.transfer(address(claimManagerContract), claimManagerAllocation);
        usdc.transfer(address(investmentManagerContract), balance);

        emit RevenueTransferred(balance);
    }

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
