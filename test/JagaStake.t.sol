// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/JagaStake.sol";
import "../src/mock/MockUSDC.sol";
import "../src/JagaToken.sol";
import "../src/InsuranceManager.sol";
import "../src/ClaimManager.sol";

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

        insuranceManager = new InsuranceManager(address(usdc), 90e6, 30 days);
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

    function testRevertDoubleClaim() public {
        vm.startPrank(user);
        usdc.approve(address(jagaStake), 1000e6);
        jagaStake.stake(1000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 62 days);

        vm.startPrank(owner);
        usdc.mint(address(insuranceManager), 100e6);
        insuranceManager.setApproval(100e6);
        insuranceManager.transferRevenue(1);
        vm.stopPrank();

        vm.startPrank(user);
        jagaStake.claim(1);
        vm.expectRevert("Already claimed");
        jagaStake.claim(1);
        vm.stopPrank();
    }
}
