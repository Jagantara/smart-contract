// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {JagaStake} from "../src/JagaStake.sol";
import {JagaToken} from "../src/JagaToken.sol";
import {MockUSDC} from "../src/mock/MockUSDC.sol";

contract JagaStakeTest is Test {
    JagaStake public jagaStake;
    MockUSDC public usdc;
    address public alice = address(1);
    address public bob = address(2);

    function setUp() public {
        usdc = new MockUSDC();
        jagaStake = new JagaStake(address(usdc));

        // Mint and approve USDC for users
        usdc.mint(alice, 1000e6);
        usdc.mint(bob, 1000e6);

        vm.prank(alice);
        usdc.approve(address(jagaStake), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(jagaStake), type(uint256).max);

        // Set insurance manager to this contract
        jagaStake.setConfig(address(this), address(99));
    }

    function testStake() public {
        vm.prank(alice);
        jagaStake.stake(100e6);

        assertEq(jagaStake.balanceOf(alice), 100e6);
        assertEq(usdc.balanceOf(address(jagaStake)), 100e6);
    }

    function testUnstake() public {
        vm.startPrank(alice);
        jagaStake.stake(200e6);
        jagaStake.unstake(200e6);
        vm.stopPrank();

        assertEq(jagaStake.balanceOf(alice), 0);
        assertEq(usdc.balanceOf(alice), 1000e6);
    }

    function testNotifyRewardAndClaim() public {
        // Stake first
        vm.prank(alice);
        jagaStake.stake(100e6);

        // Wait a bit to accumulate time
        skip(3 days);

        // Notify reward
        usdc.mint(address(this), 500e6);
        usdc.approve(address(jagaStake), 500e6);
        jagaStake.notifyRewardAmount(500e6);

        skip(30 days);

        // Claim
        uint256 reward = jagaStake.earned(alice);
        assertGt(reward, 495e6);
        vm.prank(alice);
        jagaStake.claim();

        // Check reward received
        uint256 balance = usdc.balanceOf(alice);
        console.log(balance); // 1397664000
        assertGt(balance, 900e6 + 495e6); // Initial balance (1000e6 - 100e6) + estimation reward accumulated
    }

    function testNotifyRewardAndClaimAfter() public {
        // Notify reward first
        usdc.mint(address(this), 500e6);
        usdc.approve(address(jagaStake), 500e6);
        jagaStake.notifyRewardAmount(500e6);

        // Wait a bit to accumulate time
        skip(3 days);

        // Stake
        vm.prank(alice);
        jagaStake.stake(100e6);

        skip(30 days);

        // Claim
        uint256 reward = jagaStake.earned(alice);
        assertLt(reward, 495e6);
        vm.prank(alice);
        jagaStake.claim();

        // Check reward received
        uint256 balance = usdc.balanceOf(alice);
        console.log(balance); // 1397664000
        assertLt(balance, 900e6 + 495e6); // Initial balance (1000e6 - 100e6) + estimation reward accumulated
    }

    function testNotifyRewardRevertIfNotInsuranceManager() public {
        vm.prank(bob);
        vm.expectRevert("Only insurance manager");
        jagaStake.notifyRewardAmount(100e6);
    }

    function testEmergencyWithdrawRevertIfNotClaimManager() public {
        vm.prank(address(50));
        vm.expectRevert("Invalid user");
        jagaStake.withdraw(100e6);
    }
}
