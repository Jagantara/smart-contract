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

import {IJagaStake} from "./interfaces/IJagaStake.sol";

/**
 * @title ClaimManager
 * @notice Manages claim payouts to users once they are approved by DAO governance.
 * @dev Claims must be approved by DAO and can only be withdrawn within 7 days of approval.
 */
contract ClaimManager {
    address public usdc;
    address public daoGovernance;
    address public jagaStake;
    address public owner;

    /// @notice Tracks if a claim has already been paid
    mapping(uint256 => bool) public claimExecuted;

    event ClaimPaid(
        uint256 indexed claimId,
        address indexed to,
        uint256 indexed amount
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

    /**
     * @notice Allows a claimant to withdraw their approved claim payout.
     * @dev Will pull funds from the JagaStake contract if this vault has insufficient balance.
     * @param claimId The ID of the claim being paid out.
     */
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

        // Pull missing funds from the staking contract if necessary
        if (amount > IERC20(usdc).balanceOf(address(this))) {
            uint256 amountRequired = amount -
                IERC20(usdc).balanceOf(address(this));
            IJagaStake(jagaStake).withdraw(amountRequired);
        }

        claimExecuted[claimId] = true;
        require(IERC20(usdc).transfer(claimant, amount), "Payout failed");

        emit ClaimPaid(claimId, claimant, amount);
    }

    /**
     * @notice Returns the current USDC balance of this contract (vault).
     * @return The balance of USDC in this contract.
     */
    function vaultBalance() external view returns (uint256) {
        return IERC20(usdc).balanceOf(address(this));
    }

    /**
     * @notice Sets the configuration for DAO governance and staking contracts.
     * @dev Only callable by the contract owner.
     * @param _daoGovernance The address of the DAO governance contract.
     * @param _jagaStake The address of the JagaStake staking contract.
     */
    function setConfig(
        address _daoGovernance,
        address _jagaStake
    ) external onlyOwner {
        daoGovernance = _daoGovernance;
        jagaStake = _jagaStake;
    }
}
