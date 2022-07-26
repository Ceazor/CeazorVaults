// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

interface IGasPrice {
    function maxGasPrice() external returns (uint);
}