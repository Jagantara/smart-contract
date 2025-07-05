// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import "../src/InsuranceManager.sol";
import "../src/JagaStake.sol";
import "../src/JagaToken.sol";
import "../src/DAOGovernance.sol";
import "../src/ClaimManager.sol";
import "../src/InvestmentManager.sol";
import "../src/mock/MockUSDC.sol";

contract DeployJagantara is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy Mock USDC first
        MockUSDC usdc = new MockUSDC();
        console2.log("USDC deployed at:", address(usdc));

        // Deploy main contracts
        InsuranceManager insuranceManager = new InsuranceManager(
            address(usdc),
            65e6,
            145e6,
            205e6,
            30 days
        );
        JagaStake jagaStake = new JagaStake(address(usdc));
        JagaToken jagaToken = JagaToken(jagaStake.getJagaToken());
        DAOGovernance dao = new DAOGovernance(
            address(jagaToken),
            address(insuranceManager)
        );
        ClaimManager claimManager = new ClaimManager(address(usdc));
        InvestmentManager investmentManager = new InvestmentManager(
            deployer,
            address(usdc)
        );

        // Set configurations:
        insuranceManager.setConfig(
            address(jagaStake),
            address(claimManager),
            address(investmentManager)
        );
        jagaStake.setConfig(address(insuranceManager), address(claimManager));
        dao.setConfig(address(jagaToken), address(insuranceManager));
        investmentManager.setConfig(address(jagaStake));
        claimManager.setConfig(address(dao), address(jagaStake));

        vm.stopBroadcast();

        console.log("InsuranceManager deployed at:", address(insuranceManager));
        console.log("JagaStake deployed at:", address(jagaStake));
        console.log("JagaToken deployed at:", address(jagaToken));
        console.log("DAOGovernance deployed at:", address(dao));
        console.log("ClaimManager deployed at:", address(claimManager));
        console.log(
            "InvestmentManager deployed at:",
            address(investmentManager)
        );
    }
}
