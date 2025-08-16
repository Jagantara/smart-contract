// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/InsuranceManager.sol";
import "../src/JagaStake.sol";
import "../src/JagaToken.sol";
import "../src/DAOGovernance.sol";
import "../src/ClaimManager.sol";
import "../src/MorphoReinvest.sol";
import "../src/mock/MockUSDC.sol";
import "../src/mock/MockMorphoVault.sol";

contract DeployJagantara is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Mock USDC
        MockUSDC usdc = new MockUSDC();
        console2.log("USDC deployed at:", address(usdc));

        // Deploy Mock Morpho Vault
        MockMorphoVault morpho = new MockMorphoVault(address(usdc));
        console2.log("Morpho deployed at:", address(morpho));

        // Deploy main contracts
        InsuranceManager insuranceManager = new InsuranceManager(
            address(usdc),
            100,
            300,
            500,
            30 days
        );
        JagaStake jagaStake = new JagaStake(address(usdc));
        JagaToken jagaToken = JagaToken(jagaStake.getJagaToken());
        DAOGovernance dao = new DAOGovernance(
            address(jagaToken),
            address(insuranceManager)
        );
        ClaimManager claimManager = new ClaimManager(address(usdc));
        MorphoReinvest morphoReinvest = new MorphoReinvest(
            address(morpho),
            address(usdc)
        );

        // Set configurations:
        insuranceManager.setConfig(
            address(jagaStake),
            address(claimManager),
            address(morphoReinvest)
        );
        jagaStake.setConfig(address(insuranceManager), address(claimManager));
        dao.setConfig(address(jagaToken), address(insuranceManager));
        claimManager.setConfig(address(dao), address(jagaStake));

        vm.stopBroadcast();

        console.log("InsuranceManager deployed at:", address(insuranceManager));
        console.log("JagaStake deployed at:", address(jagaStake));
        console.log("JagaToken deployed at:", address(jagaToken));
        console.log("DAOGovernance deployed at:", address(dao));
        console.log("ClaimManager deployed at:", address(claimManager));
        console.log("MorphoReinvest deployed at:", address(morphoReinvest));
    }
}
