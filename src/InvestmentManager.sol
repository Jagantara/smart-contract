// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IJagaStake {
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claim(uint256 sessionId) external;
}

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

    // Owner-controlled withdrawal (for DAO use or rebalancing)
    function withdraw(address to, uint256 amount) external onlyOwner {
        require(usdc.transfer(to, amount), "Withdraw failed");
        emit Withdrawn(to, amount);
    }

    function stake() external onlyOwner {
        uint256 usdcBalance = vaultBalance();
        totalStaked += usdcBalance;
        IJagaStake(jagaStakeAddress).stake(usdcBalance);
    }

    function unstake(uint256 amount) external onlyOwner {
        totalStaked -= amount;
        IJagaStake(jagaStakeAddress).unstake(amount);
    }

    function claim(uint256 sessionId) external onlyOwner {
        IJagaStake(jagaStakeAddress).claim(sessionId);
    }

    /// @notice Call any function with custom params
    /// @param target Address of the contract to call
    /// @param funcSignature The function signature (e.g. "foo(uint256,address)")
    /// @param params Encoded parameters (use abi.encode(...) externally)
    function callFunction(
        address target,
        string calldata funcSignature,
        bytes calldata params
    ) external onlyOwner returns (bool success, bytes memory result) {
        // Build function selector from string
        bytes4 selector = bytes4(keccak256(bytes(funcSignature)));

        // Merge selector and encoded params
        bytes memory data = abi.encodePacked(selector, params);

        // Call the target contract
        (success, result) = target.call(data);
        require(success, "Transaction Failed");
    }

    // View current balance
    function vaultBalance() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    function getAmountStaked() public view returns (uint256) {
        return totalStaked;
    }

    function setConfig(address _jagaStake) external onlyOwner {
        jagaStakeAddress = _jagaStake;
    }
}
