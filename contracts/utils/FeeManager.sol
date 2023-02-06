// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.11;

abstract contract FeeManager is Ownable {
    uint256 public constant MAX_STRATEGIST_FEE = 100;
    uint256 public constant MAX_TOTAL_FEE = 500;
    uint256 public constant MULTIPLIER = 1000;

    uint256 public totalFee = 10; //10 = 1%
    uint256 public stratFee = 500; // 500 = 50% of totalFee
    uint256 public xCheeseRate = 60; //preset to keep 60% of the reward token

    address public perFeeRecipient =
        address(0x699675204aFD7Ac2BB146d60e4E3Ddc243843519); //preset to owner
    address public strategist =
        address(0x3c5Aac016EF2F178e8699D6208796A2D67557fe2); // preset to ceazor                                                     // Who gets the strategy fee
    address public xCheeseRecipient =
        address(0x699675204aFD7Ac2BB146d60e4E3Ddc243843519); // preset to owner CHANGE ASAP
    address public keeper = address(0x6EDe1597c05A0ca77031cBA43Ab887ccf24cd7e8); //preset to Gelato on Fantom

    function setTotalFee(uint256 _totalFee) public onlyOwner {
        require(_totalFee <= MAX_TOTAL_FEE, "cant tax that much");
        totalFee = _totalFee;
    }

    function setStrategistFee(uint256 _stratFee) public onlyOwner {
        require(_stratFee <= MAX_STRATEGIST_FEE, "you taking too much");
    }

    // this rate determines how much of the profit, post fees,
    // is sent to xCheese farms.
    // this number is set as a %
    // so 60 means 60% is sent to xCheese
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

    // keeper is to grant harvest() rights
    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
    }
}
