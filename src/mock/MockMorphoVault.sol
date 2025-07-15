// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMockMorphoVault {
    function asset() external view returns (address);
    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares);
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);
    function maxRedeem(address owner) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function balances(address user) external view returns (uint256);
}

interface IDistributor {
    function claim(
        address account,
        address reward,
        uint256 claimable,
        bytes32[] calldata proof
    ) external returns (uint256 amount);
}

contract MockMorphoVault is IMockMorphoVault {
    IERC20 public immutable _asset;
    uint256 public totalAssets;
    mapping(address => uint256) public balances;

    constructor(address assetAddress) {
        _asset = IERC20(assetAddress);
    }

    function asset() external view returns (address) {
        return address(_asset);
    }

    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        shares = assets;

        // Transfer the tokens from sender to vault
        require(
            _asset.transferFrom(msg.sender, address(this), assets),
            "Transfer failed"
        );

        balances[receiver] += shares;
        totalAssets += assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares) {
        shares = assets;
        require(totalAssets >= shares, "Insufficient assets");

        balances[owner] -= shares;
        totalAssets -= shares;

        // Transfer tokens to receiver
        require(_asset.transfer(receiver, shares), "Transfer failed");
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets) {
        assets = shares;
        require(totalAssets >= shares, "Insufficient assets");

        balances[owner] -= shares;
        totalAssets -= shares;

        // Transfer tokens to receiver
        require(_asset.transfer(receiver, shares), "Transfer failed");
    }

    function maxRedeem(address owner) external view returns (uint256) {
        return balances[owner];
    }
}
