// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MorphoReinvest.sol";
import "../src/mock/MockMorphoVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/mock/MockUSDC.sol";

contract MorphoReinvestTest is Test {
    MorphoReinvest public reinvest;
    MockMorphoVault public mockVault;
    MockUSDC public usdc;

    address owner = address(1);
    address user = address(2);

    function setUp() public {
        usdc = new MockUSDC();
        mockVault = new MockMorphoVault(address(usdc));

        vm.prank(owner);
        reinvest = new MorphoReinvest(address(mockVault), address(usdc));

        // Mint USDC to owner and approve
        usdc.mint(owner, 1_000_000e6);
        vm.startPrank(owner);
        usdc.approve(address(reinvest), type(uint256).max);
        usdc.approve(address(mockVault), type(uint256).max);
        vm.stopPrank();
    }

    function testDepositAndWithdraw() public {
        uint256 depositAmount = 500e6;

        vm.startPrank(owner);
        usdc.transfer(address(reinvest), depositAmount);

        // Deposit into vault via MorphoReinvest
        reinvest.depositInVault(depositAmount);
        assertEq(mockVault.totalAssets(), depositAmount);
        assertEq(mockVault.balances(address(reinvest)), depositAmount);
        assertEq(reinvest.totalReinvested(), depositAmount);
        vm.stopPrank();
    }

    function testWithdrawFromVault() public {
        uint256 depositAmount = 500e6;

        vm.startPrank(owner);
        usdc.transfer(address(reinvest), depositAmount);
        reinvest.depositInVault(depositAmount);

        uint256 withdrawAmount = 200e6;
        reinvest.withdrawFromVaultAmount(withdrawAmount);
        assertEq(mockVault.totalAssets(), depositAmount - withdrawAmount);
        assertEq(usdc.balanceOf(address(reinvest)), withdrawAmount);
        vm.stopPrank();
    }

    function testRedeemAll() public {
        uint256 depositAmount = 500e6;

        vm.startPrank(owner);
        usdc.transfer(address(reinvest), depositAmount);
        reinvest.depositInVault(depositAmount);
        reinvest.redeemAllFromVault();

        assertEq(mockVault.totalAssets(), 0);
        assertEq(usdc.balanceOf(address(reinvest)), depositAmount);
        vm.stopPrank();
    }

    function testWithdrawUSDC() public {
        uint256 depositAmount = 500e6;

        vm.startPrank(owner);
        usdc.transfer(address(reinvest), depositAmount);
        reinvest.withdraw(owner, depositAmount);
        assertEq(usdc.balanceOf(owner), 1_000_000e6);
        vm.stopPrank();
    }
}
