
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

interface IBalancerGaugeHelper {
  function CLAIM_FREQUENCY (  ) external view returns ( uint256 );
  function CLAIM_SIG (  ) external view returns ( bytes32 );
  function claimRewards ( address gauge, address user ) external;
  function pendingRewards ( address gauge, address user, address token ) external returns ( uint256 );
}