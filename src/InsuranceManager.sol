// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IClaimManager {
    function receiveRevenue(uint256 amount) external;
}

contract InsuranceManager {
    address public owner;
    address public jagaStakeContract;
    address public claimManagerContract;
    address public InvestmentManagerContract;
    uint256 public premiumPrice;

    IERC20 public usdc;

    struct Policy {
        uint256 lastPaidAt;
        bool active;
    }

    mapping(address => Policy) public policies;

    uint256 public lastRevenueTransfer;
    uint256 public totalCollected;

    event PremiumPaid(address indexed user, uint256 amount);
    event RevenueTransferred(address to, uint256 amount);

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
        lastRevenueTransfer = block.timestamp;
        premiumDuration = _premiumDuration;
    }

    function payPremium() external {
        require(
            usdc.transferFrom(msg.sender, address(this), premiumPrice),
            "Transfer failed"
        );

        policies[msg.sender].lastPaidAt = block.timestamp;
        policies[msg.sender].active = true;
        totalCollected += PREMIUM;

        emit PremiumPaid(msg.sender, PREMIUM);
    }

    function isActive(address user) public view returns (bool) {
        Policy memory p = policies[user];
        return p.active && block.timestamp <= p.lastPaidAt + premiumDuration;
    }

    function transferRevenue() external onlyOwner {
        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, "No revenue");

        uint256 jagaStakeAllocation = (30 * balance) / 100;
        uint256 ownerAllocation = (20 * balance) / 100;
        uint256 claimManagerAllocation = (25 * balance) / 100;

        lastRevenueTransfer = block.timestamp;
        usdc.transfer(address(jagaStakeContract), jagaStakeAllocation);
        usdc.transfer(address(owner), ownerAllocation);
        usdc.transfer(address(claimManagerContract), claimManagerAllocation);
        usdc.transfer(address(InvestmentManagerContract), balance);

        emit RevenueTransferred(balance);
    }
}
