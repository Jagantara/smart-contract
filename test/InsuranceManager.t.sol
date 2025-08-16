// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/InsuranceManager.sol";
import "../src/ClaimManager.sol";
import "../src/JagaStake.sol";
import "../src/MorphoReinvest.sol";
import "../src/DAOGovernance.sol";
import "../src/JagaToken.sol";
import "../src/mock/MockUSDC.sol";
import {console} from "forge-std/console.sol";

contract InsuranceManagerTest is Test {
    InsuranceManager insuranceManager;
    ClaimManager claimManager;
    JagaStake jagaStake;
    MorphoReinvest vault;
    DAOGovernance dao;
    JagaToken jagaToken;
    MockUSDC usdc;
    address owner = address(0x1);
    address user = address(0x2);

    function setUp() public {
        vm.startPrank(owner);
        usdc = new MockUSDC();
        insuranceManager = new InsuranceManager(
            address(usdc),
            100,
            300,
            500,
            30 days
        );
        jagaStake = new JagaStake(address(usdc));
        claimManager = new ClaimManager(address(usdc));
        vault = new MorphoReinvest(address(1), address(usdc));
        dao = new DAOGovernance(
            address(jagaStake.getJagaToken()),
            address(insuranceManager)
        );

        insuranceManager.setConfig(
            address(jagaStake),
            address(claimManager),
            address(vault)
        );

        jagaStake.setConfig(address(insuranceManager), address(claimManager));

        vm.stopPrank();
    }

    function testPayPremium() public {
        vm.prank(owner);
        usdc.mint(user, 150e6);
        vm.startPrank(user);
        usdc.approve(address(insuranceManager), 100e6);
        insuranceManager.payPremium(1, 1, owner, 1000e6);
        vm.stopPrank();

        (uint256 lastPaidAt, , , , bool active, ) = insuranceManager.policies(
            user
        );
        console.log(active);
        assertTrue(active);
        assertGt(lastPaidAt, 0);
    }

    function testRevenueDistribution() public {
        vm.startPrank(owner);
        usdc.mint(address(insuranceManager), 1_500e6);

        vm.warp(block.timestamp + 40 days);

        insuranceManager.setApproval(1_500e6);
        insuranceManager.transferRevenue(
            usdc.balanceOf(address(insuranceManager))
        );
        assertGt(usdc.balanceOf(address(claimManager)), 0);
        assertGt(usdc.balanceOf(address(jagaStake)), 0);
        assertGt(usdc.balanceOf(address(owner)), 0);
        assertGt(usdc.balanceOf(address(vault)), 0);
        vm.stopPrank();
    }
}
