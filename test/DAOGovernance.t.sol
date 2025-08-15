// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/DAOGovernance.sol";
import "../src/InsuranceManager.sol";
import "../src/MorphoReinvest.sol";
import "../src/ClaimManager.sol";
import "../src/JagaToken.sol";
import "../src/JagaStake.sol";
import "../src/mock/MockUSDC.sol";

contract DAOGovernanceTest is Test {
    ClaimManager claimManager;
    DAOGovernance dao;
    InsuranceManager insuranceManager;
    JagaToken jagaToken;
    JagaStake jagaStake;
    MockUSDC usdc;
    MorphoReinvest vault;

    address owner = address(0x1);
    address voter1 = address(0x2);
    address voter2 = address(0x3);
    address claimant = address(0x4);

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
        dao = new DAOGovernance(address(jagaToken), address(insuranceManager));
        jagaStake = new JagaStake(address(usdc));
        jagaToken = JagaToken(jagaStake.getJagaToken());
        claimManager = new ClaimManager(address(usdc));
        vault = new MorphoReinvest(address(1), address(usdc));

        dao.setConfig(address(jagaToken), address(insuranceManager));
        vm.stopPrank();

        vm.startPrank(address(jagaStake));
        jagaToken.mint(voter1, 500e6);
        jagaToken.mint(voter2, 500e6);
        jagaToken.mint(claimant, 0);
        vm.stopPrank();

        vm.startPrank(owner);
        usdc.mint(claimant, 100e6); // if needed
        insuranceManager.setConfig(
            address(jagaStake),
            address(claimManager),
            address(vault)
        );
        vm.stopPrank();

        vm.startPrank(claimant);
        usdc.approve(address(insuranceManager), 100e6);
        insuranceManager.payPremium(1, 1, owner, 1000e6);
        vm.stopPrank();
    }

    function testSubmitClaim() public {
        vm.prank(claimant);
        uint256 id = dao.submitClaim(
            "Drained Fund",
            "Accidently click Judol link",
            "Drain Wallet",
            200e6
        );
        (address addr, , ) = dao.getClaimData(id);
        assertEq(addr, claimant);
    }

    function testVoteAndRejectedClaim() public {
        vm.prank(claimant);
        uint256 id = dao.submitClaim(
            "Drained Fund",
            "Accidently click Judol link",
            "Drain Wallet",
            100e6
        );

        vm.prank(voter1);
        dao.vote(id, true);

        vm.prank(voter2);
        dao.vote(id, false);

        vm.warp(block.timestamp + 6 days);
        vm.prank(claimant);
        dao.executeVote(id);

        bool approved = dao.isClaimApproved(id);
        assertFalse(approved);
    }

    function testVoteAndApproveClaim() public {
        vm.prank(claimant);
        uint256 id = dao.submitClaim(
            "Drained Fund",
            "Accidently click Judol link",
            "Drain Wallet",
            100e6
        );

        vm.prank(address(jagaStake));
        jagaToken.mint(voter1, 600e6);

        vm.prank(voter1);
        dao.vote(id, true);

        vm.prank(voter2);
        dao.vote(id, false);

        vm.warp(block.timestamp + 6 days);
        vm.prank(claimant);
        dao.executeVote(id);

        bool approved = dao.isClaimApproved(id);
        assertTrue(approved);
    }

    function testClaimRejectedIfNoVotes() public {
        vm.prank(claimant);
        uint256 id = dao.submitClaim(
            "Drained Fund",
            "Accidently click Judol link",
            "Drain Wallet",
            50e6
        );

        vm.warp(block.timestamp + 6 days);
        vm.prank(claimant);
        vm.expectRevert("No participation");
        dao.executeVote(id);
    }

    function testDuplicateVoteRejected() public {
        vm.prank(claimant);
        uint256 id = dao.submitClaim(
            "Drained Fund",
            "Accidently click Judol link",
            "Drain Wallet",
            100e6
        );

        vm.prank(voter1);
        dao.vote(id, true);

        vm.expectRevert("Already voted");
        vm.prank(voter1);
        dao.vote(id, false);
    }
}
