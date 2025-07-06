// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/JagaStake.sol";
import "../src/mock/MockUSDC.sol";
import "../src/JagaToken.sol";
import "../src/InsuranceManager.sol";
import "../src/ClaimManager.sol";
import {console} from "forge-std/console.sol";

contract JagaStakeTest is Test {
    JagaStake jagaStake;
    MockUSDC usdc;
    JagaToken jagaToken;
    InsuranceManager insuranceManager;
    ClaimManager claimManager;
    address owner = address(0x1);
    address user = address(0x2);

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockUSDC();
        jagaStake = new JagaStake(address(usdc));
        insuranceManager = new InsuranceManager(
            address(usdc),
            65e6,
            145e6,
            205e6,
            30 days
        );
        insuranceManager.setConfig(address(jagaStake), owner, owner); // owner is dummy address
        jagaStake.setConfig(address(insuranceManager), address(0));
        jagaToken = jagaStake.getJagaToken();

        usdc.mint(user, 1000e6);
        vm.stopPrank();
    }

    function testStakeUSDC() public {
        vm.startPrank(user);
        usdc.approve(address(jagaStake), 500e6);
        jagaStake.stake(500e6);

        assertEq(usdc.balanceOf(address(jagaStake)), 500e6);
        assertEq(jagaStake.currentStake(user), 500e6);
        assertEq(jagaToken.balanceOf(address(user)), 500e6);
        vm.stopPrank();
    }

    function testUnstakeUSDC() public {
        vm.startPrank(user);
        usdc.approve(address(jagaStake), 500e6);
        jagaStake.stake(500e6);

        jagaStake.unstake(200e6);

        console.log(usdc.balanceOf(user));
        assertEq(usdc.balanceOf(user), 700e6); // 1000 - 500 + 200
        assertEq(jagaStake.currentStake(user), 300e6);
        assertEq(jagaToken.balanceOf(address(user)), 300e6);
        vm.stopPrank();
    }

    function testClaimReward() public {
        vm.startPrank(user);
        usdc.approve(address(jagaStake), 1000e6);
        jagaStake.stake(1000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 62 days);

        vm.startPrank(owner);
        usdc.mint(address(insuranceManager), 100e6);
        insuranceManager.setApproval(100e6);
        insuranceManager.transferRevenue(
            usdc.balanceOf(address(insuranceManager)),
            1
        );
        vm.stopPrank();

        assertEq(jagaStake.timeLeft(), 2419200); // 28 days left

        vm.startPrank(user);
        (uint256 totalStaked, uint256 totalReward, bool finalized) = jagaStake
            .getSessionInfo(1);
        console.log("Session 1 total staked:", totalStaked);
        console.log("Session 1 total reward:", totalReward);
        console.log("Session 1 finalized:", finalized);

        // For getUserSessionStake - this one works as is
        console.log(
            "User stake in session 1:",
            jagaStake.getUserSessionStake(user, 1)
        );

        // For getUserSessionsToClaim - handle the array
        uint256[] memory sessionsToClaimArray = jagaStake
            .getUserSessionsToClaim(user);
        console.log(
            "Number of sessions to claim:",
            sessionsToClaimArray.length
        );
        for (uint i = 0; i < sessionsToClaimArray.length; i++) {
            console.log("Session to claim:", sessionsToClaimArray[i]);
        }
        assertEq(jagaStake.pendingReward(), 30e6);
        jagaStake.claim();
        assertEq(usdc.balanceOf(user), 30e6); // 30% of the revenue
    }
}
