// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//FANTOM Contracts
//hUSDC - 0x04068da6c83afcfa0e13ba15a6696662335d5b75
//hMIM -  0xa8cD5D59827514BCF343EC19F531ce1788Ea48f8
//hfUSDT - 0xE4e43864ea18d5E5211352a4B810383460aB7fcC
//hFRAX - 0xb4300e088a3AE4e624EE5C71Bc1822F68BB5f2bc
//hDAI - 0x8e15a22853A0A60a0FBB0d875055A8E66cff0235

interface IHundred {
    function mint(uint mintAmount) external returns (uint);
    function balanceOf(address owner) external returns (uint256);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function exchangeRateStored() external view returns(uint256);

}