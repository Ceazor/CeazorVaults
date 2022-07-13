// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBeethovenxFBeets {
    function approve(address _spender, uint256 _ammount) external;
    function decreaseAllowance(address _spender, uint256 _ammount) external;
    function enter(uint256 _amount) external;
    function leave(uint256 _shareOfFreshBeets) external;
}