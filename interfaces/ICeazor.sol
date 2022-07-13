// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICeazor {
    function depositAll() external;
    function deposit(uint256 _amount) external;
    function withdrawAll() external;
    function withdraw(uint256 _amount) external;
}