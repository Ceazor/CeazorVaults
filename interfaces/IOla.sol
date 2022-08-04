// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;


interface IOla {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function withdrawAll() external;
    function getReward(address handler, bytes32[] memory params) external;
    function balanceOf(address farmer) external view returns (uint256);
    function earnedCurrentMinusFee(address farmer) external view returns (uint256);
}
