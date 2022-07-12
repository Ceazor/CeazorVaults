// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//FANTOM Contracts
//hUSDCtoLQDR -  0x9a07fb107b9d8ea8b82ecf453efb7cfb85a66ce9
//hMIMtoLQDR -   0xed566b089fc80df0e8d3e0ad3ad06116433bf4a7
//hfUSDTtoLQDR - ?????? no farm yet
//hFRAXtoLQDR-   0x669F5f289A5833744E830AD6AB767Ea47A3d6409
//hDAItoLQDR -   0x79364e45648db09ee9314e47b2fd31c199eb03b9

interface ILQDR {
    function deposit(uint256 pid, uint256 amount, address to) external; 
    function withdraw(uint256 amount, uint256 pid, address to) external returns (uint256); //withdraws leaving rewards
    function harvest(uint256 pid, address to) external returns(uint256); //claims rewards
    function userInfo(uint256 pid, address to)external view returns(uint256, int256); // returns hTOKENs in farm, and RewardDebt
    //withdraws amount of hTKNS inputed and harvest all rewards
    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external returns(uint256, uint256); 
}