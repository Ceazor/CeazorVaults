// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

interface IMasterChefv2 {
    function harvest(uint256 pid, address to) external;
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;
    function deposit(uint256 pid, uint256 amount, address to) external;
    function beets() external view returns (uint256);
}