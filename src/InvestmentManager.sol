// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvestmentManagerVault {
    address public owner;
    address public claimManager;
    IERC20 public immutable usdc;

    event Deposit(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event ClaimManagerFunded(address indexed to, uint256 amount);
    event ClaimManagerUpdated(address indexed newClaimManager);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyClaimManager() {
        require(msg.sender == claimManager, "Only ClaimManager");
        _;
    }

    constructor(address _usdc) {
        owner = msg.sender;
        usdc = IERC20(_usdc);
    }

    // Deposit USDC from DAO, external source, or strategy
    function deposit(uint256 amount) external {
        require(amount > 0, "Zero amount");
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        emit Deposit(msg.sender, amount);
    }

    // Owner-controlled withdrawal (for DAO use or rebalancing)
    function withdraw(address to, uint256 amount) external onlyOwner {
        require(usdc.transfer(to, amount), "Withdraw failed");
        emit Withdrawn(to, amount);
    }

    // ClaimManager requests funds for payouts
    function fundClaimManager(uint256 amount) external onlyClaimManager {
        require(usdc.transfer(claimManager, amount), "Funding failed");
        emit ClaimManagerFunded(claimManager, amount);
    }

    // Set or update the ClaimManager contract
    function setClaimManager(address _claimManager) external onlyOwner {
        claimManager = _claimManager;
        emit ClaimManagerUpdated(_claimManager);
    }

    // View current balance
    function vaultBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}
