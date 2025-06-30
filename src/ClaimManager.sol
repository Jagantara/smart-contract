// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDAOGovernance {
    function isClaimApproved(uint256 claimId) external view returns (bool);
    function getClaimData(
        uint256 claimId
    )
        external
        view
        returns (address claimant, uint256 amount, uint256 approvedAt);
}

interface IJagaStake {
    function withdraw(uint256 amount) external;
}

contract ClaimManager {
    address public usdc;
    address public daoGovernance;
    address public jagaStake;
    address public owner;

    mapping(uint256 => bool) public claimExecuted;

    event RevenueReceived(uint256 amount);
    event ClaimPaid(
        uint256 indexed claimId,
        address indexed to,
        uint256 amount
    );

    modifier onlyDAO() {
        require(msg.sender == daoGovernance, "Only DAO");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _usdc) {
        owner = msg.sender;
        usdc = _usdc;
    }

    // Claimer calls this to withdraw their claim (after DAO approval)
    function claimPayout(uint256 claimId) external {
        require(!claimExecuted[claimId], "Already paid");

        (address claimant, uint256 amount, uint256 approvedAt) = IDAOGovernance(
            daoGovernance
        ).getClaimData(claimId);

        require(claimant == msg.sender, "Not claimant");
        require(
            IDAOGovernance(daoGovernance).isClaimApproved(claimId),
            "Not approved"
        );
        require(block.timestamp <= approvedAt + 7 days, "Claim expired");

        if (amount > IERC20(usdc).balanceOf(address(this))) {
            uint256 amountRequired = amount -
                IERC20(usdc).balanceOf(address(this));
            IJagaStake(jagaStake).withdraw(amountRequired);
        }

        claimExecuted[claimId] = true;
        require(IERC20(usdc).transfer(claimant, amount), "Payout failed");

        emit ClaimPaid(claimId, claimant, amount);
    }

    // Optional: admin view of balance
    function vaultBalance() external view returns (uint256) {
        return IERC20(usdc).balanceOf(address(this));
    }

    function setConfig(
        address _daoGovernance,
        address _jagaStake
    ) external onlyOwner {
        daoGovernance = _daoGovernance;
        jagaStake = _jagaStake;
    }
}
