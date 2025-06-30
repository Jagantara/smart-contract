// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IClaimManager {
    function receiveRevenue(uint256 amount) external;
}

contract InsuranceManager {
    address public owner;
    address public revenueReceiver;
    uint256 public constant PREMIUM = 10 * 1e6; // 10 USDC (6 decimals)
    uint256 public constant CYCLE_DURATION = 30 days;

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

    constructor(address _usdc, address _claimManager) {
        owner = msg.sender;
        usdc = IERC20(_usdc);
        revenueReceiver = _claimManager;
        lastRevenueTransfer = block.timestamp;
    }

    function payPremium() external {
        require(
            usdc.transferFrom(msg.sender, address(this), PREMIUM),
            "Transfer failed"
        );

        policies[msg.sender].lastPaidAt = block.timestamp;
        policies[msg.sender].active = true;
        totalCollected += PREMIUM;

        emit PremiumPaid(msg.sender, PREMIUM);
    }

    function isActive(address user) public view returns (bool) {
        Policy memory p = policies[user];
        return p.active && block.timestamp <= p.lastPaidAt + CYCLE_DURATION;
    }

    function transferRevenue() external {
        require(
            block.timestamp >= lastRevenueTransfer + CYCLE_DURATION,
            "Too early"
        );

        uint256 balance = usdc.balanceOf(address(this));
        require(balance > 0, "No revenue");

        lastRevenueTransfer = block.timestamp;
        usdc.approve(revenueReceiver, balance);
        IClaimManager(revenueReceiver).receiveRevenue(balance);

        emit RevenueTransferred(revenueReceiver, balance);
    }

    function setClaimManager(address _claimManager) external onlyOwner {
        revenueReceiver = _claimManager;
    }
}
