// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/InvestmentManager.sol";
import "../src/JagaStake.sol"; // Only for interface, can also use Mock
import "../src/mock/MockUSDC.sol";

// Mock JagaStake
contract MockJagaStake is IJagaStake {
    IERC20 public usdc;
    uint256 public totalStaked;
    uint256 public claimedSession;

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    function stake(uint256 amount) external override {
        usdc.transferFrom(msg.sender, address(this), amount);
        totalStaked += amount;
    }

    function unstake(uint256 amount) external override {
        require(totalStaked >= amount, "Insufficient stake");
        totalStaked -= amount;
        usdc.transfer(msg.sender, amount);
    }

    function claim(uint256 sessionId) external override {
        claimedSession = sessionId;
    }

    function withdraw(uint256) external override {}

    function addRevenue(uint256 sessionId, uint256 amount) external {}
}

contract InvestmentManagerTest is Test {
    InvestmentManager vault;
    MockUSDC usdc;
    MockJagaStake mockJagaStake;
    address owner = address(1);
    address user = address(2);

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockUSDC();
        vault = new InvestmentManager(owner, address(usdc));
        mockJagaStake = new MockJagaStake(address(usdc));
        vault.setConfig(address(mockJagaStake));

        usdc.mint(address(vault), 1000e6);
        vm.stopPrank();
    }

    function testStakeUSDC() public {
        vm.startPrank(owner);
        usdc.approve(address(mockJagaStake), type(uint256).max);
        usdc.approve(address(vault), type(uint256).max);
        vault.stake();

        assertEq(mockJagaStake.totalStaked(), 1000e6);
        assertEq(vault.getAmountStaked(), 1000e6);
        vm.stopPrank();
    }

    function testUnstakeUSDC() public {
        vm.startPrank(owner);
        usdc.approve(address(mockJagaStake), type(uint256).max);
        vault.stake();

        // Unstake half
        vault.unstake(500e6);
        assertEq(mockJagaStake.totalStaked(), 500e6);
        assertEq(vault.getAmountStaked(), 500e6);
        vm.stopPrank();
    }

    function testWithdraw() public {
        vm.startPrank(owner);
        vault.withdraw(user, 100e6);
        assertEq(usdc.balanceOf(user), 100e6);
        vm.stopPrank();
    }

    function testClaimReward() public {
        vm.startPrank(owner);
        vault.claim(3);
        assertEq(mockJagaStake.claimedSession(), 3);
        vm.stopPrank();
    }

    function testRevertOnlyOwner() public {
        vm.startPrank(user);
        vm.expectRevert("Not owner");
        vault.withdraw(user, 1);
        vm.stopPrank();
    }
}
