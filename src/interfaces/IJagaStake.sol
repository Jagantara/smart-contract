// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IJagaStake {
    function withdraw(uint256 amount) external;
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claim() external;
    function notifyRewardAmount(uint256 reward) external;
}
