// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract sweeper  is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public vault; 
    address public want;        

    constructor(
        address _vault,
        address _want             // ????????????????????????????????????????/
    ) {  
        vault = _vault;
        want = _want;
    }

    function deposit() external {
        require(msg.sender == vault, "only the vault anon!");  
        IERC20(want).balanceOf(address(this));
    }

    function sweep(address _token, address _receiver) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_receiver, amount);
    }


}