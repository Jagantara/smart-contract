// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMockMorphoVault, IDistributor} from "../src/mock/MockMorphoVault.sol";

/**
 * @title MorphoReinvest
 * @notice Contract to manage USDC deposits into a Morpho Vault for reinvestment
 * @dev Only the contract owner can deposit, withdraw, redeem or claim from the vault.
 * It allows maximizing vault approval, tracking total reinvested amount, and claiming rewards.
 */
contract MorphoReinvest {
    address public morphoVault;
    uint256 public totalReinvested;
    address public owner;
    address public immutable usdc;

    event Withdrawn(address indexed to, uint256 indexed amount);
    event Approved(address indexed vault, uint256 indexed amount);
    event Deposited(address indexed vault, uint256 indexed amount);
    event WithdrawnFromVault(address indexed vault, uint256 indexed amount);
    event RedeemedFromVault(address indexed vault, uint256 indexed amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address morphoAddress, address _usdc) {
        usdc = _usdc;
        owner = msg.sender;
        morphoVault = morphoAddress;
    }

    /**
     * @notice Approves the maximum allowance for the vault if not already approved
     * @param vault The vault address to approve
     */
    function _approveMaxVault(address vault) internal {
        if (
            ERC20(IMockMorphoVault(vault).asset()).allowance(
                address(this),
                vault
            ) == 0
        ) {
            ERC20(IMockMorphoVault(vault).asset()).approve(
                vault,
                type(uint256).max
            );
            emit Approved(vault, type(uint256).max);
        }
    }

    /**
     * @notice Withdraws USDC from the vault to a specific address (for rebalancing)
     * @dev Only callable by owner
     * @param to The destination address for the withdrawn funds
     * @param amount The amount of USDC to withdraw
     */
    function withdraw(address to, uint256 amount) external onlyOwner {
        require(IERC20(usdc).transfer(to, amount), "Withdraw failed");
        emit Withdrawn(to, amount);
    }

    /**
     * @notice Deposits USDC into the vault
     * @dev Only callable by the owner
     * @param assets The amount of USDC to deposit
     * @return shares The amount of shares received from the vault
     */
    function depositInVault(
        uint256 assets
    ) public onlyOwner returns (uint256 shares) {
        _approveMaxVault(morphoVault);

        totalReinvested += assets;
        shares = IMockMorphoVault(morphoVault).deposit(assets, address(this));
        emit Deposited(morphoVault, assets);
    }

    /**
     * @notice Withdraws a specific amount of USDC from the vault
     * @dev Only callable by the owner. For withdrawing all, use redeemAllFromVault.
     * @param assets The amount of USDC to withdraw
     * @return redeemed The amount of shares redeemed
     */
    function withdrawFromVaultAmount(
        uint256 assets
    ) public onlyOwner returns (uint256 redeemed) {
        totalReinvested -= assets;
        redeemed = IMockMorphoVault(morphoVault).withdraw(
            assets,
            address(this),
            address(this)
        );
        emit WithdrawnFromVault(morphoVault, assets);
    }

    /**
     * @notice Redeems all available shares from the vault
     * @dev Only callable by the owner
     * @return redeemed The amount of USDC redeemed
     */
    function redeemAllFromVault() public onlyOwner returns (uint256 redeemed) {
        uint256 maxToRedeem = IMockMorphoVault(morphoVault).maxRedeem(
            address(this)
        );
        uint256 totalRedeemed = totalReinvested;
        totalReinvested = 0;
        redeemed = IMockMorphoVault(morphoVault).redeem(
            maxToRedeem,
            address(this),
            address(this)
        );
        emit RedeemedFromVault(morphoVault, totalRedeemed);
    }

    function setMorphoVault(address morphoAddress) public onlyOwner {
        morphoVault = morphoAddress;
    }

    /**
     * @notice Claims rewards via an external distributor contract based on morpho documentation
     * @dev Only callable by the owner
     * @param distributor The distributor contract address
     * @param user The address of the user to claim for
     * @param asset The reward asset address
     * @param claimable The amount of rewards claimable
     * @param proof The Merkle proof required by the distributor
     */
    function claim(
        address distributor,
        address user,
        address asset,
        uint256 claimable,
        bytes32[] calldata proof
    ) public onlyOwner returns (uint256 amount) {
        amount = IDistributor(distributor).claim(user, asset, claimable, proof);
    }
}
