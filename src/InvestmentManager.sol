// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IJagaStake} from "./interfaces/IJagaStake.sol";

/**
 * @title InvestmentManagerVault
 * @notice Manages staking USDC into JagaStake and allows owner to withdraw or interact with other contracts
 * @dev Only the owner can perform staking, unstaking, revenue claiming, and arbitrary contract calls
 */
contract InvestmentManagerVault {
    address public owner;
    address public jagaStakeAddress;
    IERC20 public immutable usdc;
    uint256 totalStaked;

    event Withdrawn(address indexed to, uint256 indexed amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _owner, address _usdc) {
        owner = _owner;
        usdc = IERC20(_usdc);
    }

    /**
     * @notice Withdraws USDC from the vault to a specific address (for rebalancing)
     * @dev Only callable by owner
     * @param to The destination address for the withdrawn funds
     * @param amount The amount of USDC to withdraw
     */
    function withdraw(address to, uint256 amount) external onlyOwner {
        require(usdc.transfer(to, amount), "Withdraw failed");
        emit Withdrawn(to, amount);
    }

    /**
     * @notice Stakes the entire USDC balance in the vault into the JagaStake contract
     * @dev Only callable by owner. Updates `totalStaked`.
     */
    function stake() external onlyOwner {
        uint256 usdcBalance = vaultBalance();
        totalStaked += usdcBalance;
        IJagaStake(jagaStakeAddress).stake(usdcBalance);
    }

    /**
     * @notice Unstakes a specific amount of USDC from JagaStake
     * @dev Only callable by owner. Decreases `totalStaked`.
     * @param amount The amount of USDC to unstake
     */
    function unstake(uint256 amount) external onlyOwner {
        totalStaked -= amount;
        IJagaStake(jagaStakeAddress).unstake(amount);
    }

    /**
     * @notice Claims rewards from JagaStake for a specific session
     * @dev Only callable by owner
     * @param sessionId The session ID to claim rewards from
     */
    function claim(uint256 sessionId) external onlyOwner {
        IJagaStake(jagaStakeAddress).claim(sessionId);
    }

    function vaultBalance() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /**
     * @notice Returns the total amount of USDC that has been staked
     * @return The total amount currently marked as staked
     */
    function getAmountStaked() public view returns (uint256) {
        return totalStaked;
    }

    /**
     * @notice Sets the configuration for JagaStake contracts.
     * @dev Only callable by the contract owner.
     * @param _jagaStake The address of the Jaga stake contract.
     */
    function setConfig(address _jagaStake) external onlyOwner {
        jagaStakeAddress = _jagaStake;
    }
}
