// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.11;


abstract contract FeeManager is Ownable {
    uint constant public STRATEGIST_FEE = 112;
    uint constant public MAX_FEE = 1000;
    uint constant public MAX_TOTAL_FEE = 50;
    uint constant public WITHDRAWAL_FEE_CAP = 50;
    uint constant public WITHDRAWAL_MAX = 10000;

    uint public totalFee = 10;
    uint public withdrawalFee = 10;                         
    uint public perFee = MAX_FEE - STRATEGIST_FEE;
    uint public xCheeseRate = 60;  //preset to keep 60% of the reward token

    address public perFeeRecipient = address(0x699675204aFD7Ac2BB146d60e4E3Ddc243843519);    //preset to owner  
    address public strategist = address(0x3c5Aac016EF2F178e8699D6208796A2D67557fe2);         // preset to ceazor                                                     // Who gets the strategy fee
    address public xCheeseRecipient = address(0x699675204aFD7Ac2BB146d60e4E3Ddc243843519);  // preset to owner CHANGE ASAP


    function setTotalFee(uint256 _totalFee) public onlyOwner {
        require(_totalFee <= MAX_TOTAL_FEE, "!cap");
        totalFee = _totalFee;
    }
    function setWithdrawalFee(uint256 _fee) public onlyOwner {
        require(_fee <= WITHDRAWAL_FEE_CAP, "!cap");
        withdrawalFee = _fee;
    }
    function setStrategistFee(uint256 _stratFee)public onlyOwner {
        require(_stratFee <= MAX_FEE, "you taking too much");
    }

    // this rate determines how much of the profit, post fees,
    // is sent to xCheese farms.
    // this number is set as a %
    // so 40 means 40% is sent to xCheese
    function setxCheeseRate(uint256 _rate) public onlyOwner { 
        xCheeseRate = _rate;                                     
    }

    // set the recipients of fee transfers
    function setStrategist(address _strategist) public onlyOwner {
        strategist = _strategist;
    }
    function setperFeeRecipient(address _perFeeRecipient) public onlyOwner {
        perFeeRecipient = _perFeeRecipient;
    }
    function setxCheeseRecipient(address _address) public onlyOwner {
        xCheeseRecipient = _address;
    }
}