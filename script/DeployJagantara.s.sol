// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/InsuranceManager.sol";
import "../src/JagaStake.sol";
import "../src/JagaToken.sol";
import "../src/DAOGovernance.sol";
import "../src/ClaimManager.sol";
import "../src/InvestmentManager.sol";

contract DeployJagantara is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY"); // Using CLI flag, can pass dummy here
        address usdc = vm.envAddress("USDC_ADDRESS"); // USDC already deployed on Monad

        vm.startBroadcast(deployerPrivateKey);

        // Deploy main contracts
        InsuranceManager insuranceManager = new InsuranceManager(
            usdc,
            90e6,
            30 days
        );
        JagaStake jagaStake = new JagaStake(usdc);
        JagaToken jagaToken = JagaToken(jagaStake.getJagaToken());
        DAOGovernance dao = new DAOGovernance(
            address(jagaToken),
            address(insuranceManager)
        );
        ClaimManager claimManager = new ClaimManager(usdc);
        InvestmentManager vault = new InvestmentManager(msg.sender, usdc);

        // Set configurations:
        insuranceManager.setConfig(
            address(jagaStake),
            address(claimManager),
            address(vault)
        );
        jagaStake.setConfig(address(insuranceManager), address(claimManager));
        dao.setConfig(address(jagaToken), address(insuranceManager));
        vault.setConfig(address(jagaStake));
        claimManager.setConfig(address(dao), address(jagaStake));

        vm.stopBroadcast();

        console.log("InsuranceManager deployed at:", address(insuranceManager));
        console.log("JagaStake deployed at:", address(jagaStake));
        console.log("JagaToken deployed at:", address(jagaToken));
        console.log("DAOGovernance deployed at:", address(dao));
        console.log("ClaimManager deployed at:", address(claimManager));
        console.log("InvestmentManager deployed at:", address(vault));
    }
}
