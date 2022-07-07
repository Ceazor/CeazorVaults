// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.11;


abstract contract FeeManager is Ownable {
    uint constant public STRATEGIST_FEE = 112;
    uint constant public MAX_FEE = 1000;
    uint constant public MAX_CALL_FEE = 111;
    uint constant public MAX_TOTAL_FEE = 50;
    uint constant public WITHDRAWAL_FEE_CAP = 50;
    uint constant public WITHDRAWAL_MAX = 10000;

    uint public totalFee = 10;
    uint public withdrawalFee = 10;
    uint public callFee = 111;
    uint public perFee = MAX_FEE - STRATEGIST_FEE - callFee;
    uint public xCheeseRate = 2;

    function setTotalFee(uint256 _totalFee) public onlyOwner {
        require(_totalFee <= MAX_TOTAL_FEE, "!cap");

        totalFee = _totalFee;
    }

    function setCallFee(uint256 _fee) public onlyOwner {
        require(_fee <= MAX_CALL_FEE, "!cap");
        
        callFee = _fee;
        perFee = MAX_FEE - STRATEGIST_FEE - callFee;
    }

    function setWithdrawalFee(uint256 _fee) public onlyOwner {
        require(_fee <= WITHDRAWAL_FEE_CAP, "!cap");

        withdrawalFee = _fee;
    }

    // this rate determines how much of the profit, post fees, is
    // is converted back to the reward token and sent to xCheese farms.
    // this number is to be .div, so if set to 
    // 0 = nothing will be sent
    // 1 = ALL profts will be sent ???? brick?? can't be set to 1
    // 2 = half sent
    // 4 = 25 percent sent
    function setxCheeseRate(uint256 _rate) public onlyOwner {
        require(_rate != 1, "can't set this to 1"); 
        xCheeseRate = _rate;                                     
    }
}