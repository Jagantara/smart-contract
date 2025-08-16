// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/ClaimManager.sol";
import "../src/DAOGovernance.sol";
import "../src/InsuranceManager.sol";
import "../src/JagaStake.sol";
import "../src/JagaToken.sol";
import "../src/mock/MockUSDC.sol";
import {console} from "forge-std/console.sol";

contract ClaimManagerTest is Test {
    ClaimManager claimManager;
    DAOGovernance dao;
    InsuranceManager insuranceManager;
    JagaStake jagaStake;
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
        claimManager = new ClaimManager(address(usdc));
        jagaStake = new JagaStake(address(usdc));
        jagaToken = JagaToken(jagaStake.getJagaToken());
        dao = new DAOGovernance(address(jagaToken), address(insuranceManager));

        claimManager.setConfig(address(dao), address(jagaStake));
        vm.stopPrank();
    }

    function testClaimPayoutSuccess() public {
        // Register user and give voting power
        vm.prank(owner);
        usdc.mint(user, 100e6);

        vm.prank(user);
        usdc.approve(address(insuranceManager), 100e6);
        vm.prank(user);
        insuranceManager.payPremium(1, 1, owner, 1000e6);

        // Submit and approve a claim
        vm.prank(user);
        uint256 claimId = dao.submitClaim(
            "Drained Fund",
            "Accidently click Judol link",
            "Drain Wallet",
            100e6
        );

        vm.prank(address(jagaStake));
        jagaToken.mint(owner, 1000e6);

        vm.prank(owner);
        dao.vote(claimId, true);

        vm.warp(block.timestamp + 5 days);
        vm.prank(user);
        dao.executeVote(claimId);

        // Fund ClaimManager
        vm.prank(owner);
        usdc.mint(address(claimManager), 100e6);
        assertEq(claimManager.vaultBalance(), 100e6);

        // Claim payout
        vm.prank(user);
        claimManager.claimPayout(claimId);

        assertEq(usdc.balanceOf(user), 199e6);
        assertTrue(claimManager.claimExecuted(claimId));
    }

    function testCannotDoubleClaim() public {
        vm.prank(owner);
        usdc.mint(user, 1000e6);
        vm.prank(user);
        usdc.approve(address(insuranceManager), 100e6);
        vm.prank(user);
        insuranceManager.payPremium(1, 1, owner, 1000e6);

        vm.prank(user);
        uint256 claimId = dao.submitClaim(
            "Drained Fund",
            "Accidently click Judol link",
            "Drain Wallet",
            100e6
        );

        vm.prank(address(jagaStake));
        jagaToken.mint(owner, 1000e6);
        vm.prank(owner);
        dao.vote(claimId, true);

        vm.warp(block.timestamp + 5 days);
        vm.prank(user);
        dao.executeVote(claimId);

        vm.prank(owner);
        usdc.mint(address(claimManager), 100e6);

        vm.prank(user);
        claimManager.claimPayout(claimId);

        // Second call should revert
        vm.expectRevert("Already paid");
        vm.prank(user);
        claimManager.claimPayout(claimId);
    }
}
