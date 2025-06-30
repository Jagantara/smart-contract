// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDAOGovernance {
    function isClaimApproved(uint256 claimId) external view returns (bool);
    function getClaimData(
        uint256 claimId
    )
        external
        view
        returns (address claimant, uint256 amount, uint256 approvedAt);
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address addr) external view returns (uint256);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract ClaimManager {
    address public usdc;
    address public dao;

    mapping(uint256 => bool) public claimExecuted;

    event RevenueReceived(uint256 amount);
    event ClaimPaid(
        uint256 indexed claimId,
        address indexed to,
        uint256 amount
    );

    modifier onlyDAO() {
        require(msg.sender == dao, "Only DAO");
        _;
    }

    constructor(address _usdc, address _dao) {
        usdc = _usdc;
        dao = _dao;
    }

    // Called by InsuranceManager every 30 days
    function receiveRevenue(uint256 amount) external {
        require(
            IERC20(usdc).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        emit RevenueReceived(amount);
    }

    // Claimer calls this to withdraw their claim (after DAO approval)
    function claimPayout(uint256 claimId) external {
        require(!claimExecuted[claimId], "Already paid");

        (address claimant, uint256 amount, uint256 approvedAt) = IDAOGovernance(
            dao
        ).getClaimData(claimId);

        require(claimant == msg.sender, "Not claimant");
        require(IDAOGovernance(dao).isClaimApproved(claimId), "Not approved");
        require(block.timestamp <= approvedAt + 7 days, "Claim expired");

        claimExecuted[claimId] = true;
        require(IERC20(usdc).transfer(claimant, amount), "Payout failed");

        emit ClaimPaid(claimId, claimant, amount);
    }

    // Optional: admin view of balance
    function vaultBalance() external view returns (uint256) {
        return IERC20(usdc).balanceOf(address(this));
    }
}
