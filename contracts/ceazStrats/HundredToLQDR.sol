// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IBalancerVault.sol";
import "../../interfaces/IHundred.sol";
import "../../interfaces/ILQDR.sol";
import "../strategies/FeeManager.sol";

contract HundredToLQDR is FeeManager, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // essentials
    address public vault; 
    address public want;
    address public HND = address(0x10010078a54396F62c96dF8532dc2B4847d47ED3);    //HND token
    address public native = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83); //wftm but if pool doesnt use need to change this
    address public hToken;

    //farm stuff
    address public LQDRFarm;
    uint256 public LQDRPid;    
    address public unirouter = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);         // HND Swap route (The VAULT on Beets)
    bytes32 public HNDSwapPoolId = bytes32(0x843716e9386af1a26808d8e6ce3948d606ff115a00020000000000000000043a); //HND:wFTM 60/40 BPool
    bytes32 public wantPoolId;

    address public perFeeRecipient;                                                         // Who gets the performance fee
    address public strategist;                                                              // Who gets the strategy fee
    address public xCheeseRecipient = address(0x699675204aFD7Ac2BB146d60e4E3Ddc243843519);  // preset to owner CHANGE ASAP
    uint256 public xCheeseKeepRate = 60;

    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit = bool(true);
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _vault,             //  
        address _strategist,        // 0x3c5Aac016EF2F178e8699D6208796A2D67557fe2 - ceazor
        address _perFeeRecipient,   // 0x3c5Aac016EF2F178e8699D6208796A2D67557fe2 - ceazor
        address _want,              // USDC,    MIM,    FRAX,   DAI
        address _hToken,            //
        uint256 _LQDRPid,           // 0,       1,      2,      3 
        bytes32 _wantPoolId,        //0xbb4607bede4610e80d35c15692efcb7807a2d0a6000200000000000000000140
        address _LQDRFarm           //
        
    ) {  
        vault = _vault;
        strategist = _strategist;
        perFeeRecipient = _perFeeRecipient;
        want = _want;
        hToken = _hToken;
        LQDRPid = _LQDRPid;
        LQDRFarm = _LQDRFarm;
        wantPoolId = _wantPoolId;
                

        _giveAllowances();
    }
    
    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            IHundred(hToken).mint(wantBal);
            uint256 _hTknBal = IHundred(hToken).balanceOf(address(this));
            ILQDR(LQDRFarm).deposit(LQDRPid, _hTknBal, (address(this)));
        }
    }
  
    //takes the funds out of the farm and sends them to the vault.
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "ask the vault to withdraw ser!");  //makes sure only the vault can withdraw from the chef

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            //convert want to hTknNeed
            uint256 _hTknNeed = (_amount.sub(wantBal)).div(IHundred(hToken).exchangeRateStored()); 
            //withdraw htkn from lqdr but leaves behind rewards since last harvest
            ILQDR(LQDRFarm).withdraw(_hTknNeed, LQDRPid, (address(this)));
            //redeem htkn for want
            IHundred(hToken).redeem(_hTknNeed);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            wantBal = wantBal.sub(withdrawalFeeAmount);
        }
        //return want to vault
        IERC20(want).safeTransfer(vault, _amount);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");  //makes sure the vault is the only one that can do quick preDeposit Harvest
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        ILQDR(LQDRFarm).harvest(LQDRPid, address(this));
        uint256 _hndBal = IERC20(HND).balanceOf(address(this));        
        if (_hndBal > 0) {
            chargeFees(callFeeRecipient);
            sendXCheese();
            uint256 _hndLeft = IERC20(HND).balanceOf(address(this));
            balancerSwap(HNDSwapPoolId, HND, native, _hndLeft); 
            //<-------------------------------where to swap wFTM for want?
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf()); //tells everyone who did the harvest (they need be paid)
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 _hndBal = IERC20(HND).balanceOf(address(this));        
        uint256 _totalFees = _hndBal.mul(totalFee).div(1000);
        if (_totalFees > 0) {
            balancerSwap(HNDSwapPoolId, HND, native, _totalFees);
            uint256 callFeeAmount = _totalFees.mul(callFee).div(MAX_FEE); 
            uint256 strategistFee = _totalFees.mul(STRATEGIST_FEE).div(MAX_FEE);
            uint256 perFeeAmount = _totalFees.sub(strategistFee).sub(callFeeAmount);
            IERC20(HND).safeTransfer(callFeeRecipient, callFeeAmount);
            IERC20(HND).safeTransfer(strategist, strategistFee); 
            IERC20(HND).safeTransfer(perFeeRecipient, perFeeAmount);  
        }
    }

    //ceazor keeps a % of HND set by the xCheeseRate
    function sendXCheese() internal {
        uint256 forXCheese = IERC20(HND).balanceOf(address(this)).mul(xCheeseKeepRate).div(100);
        if (forXCheese > 0) {
            IERC20(HND).safeTransfer(xCheeseRecipient, forXCheese);   // and send them to xCheese
        }
    }   

    function balancerSwap(bytes32 _poolId, address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(_poolId, swapKind, _tokenIn, _tokenOut, _amountIn, "");
        return IBalancerVault(unirouter).swap(singleSwap, funds, 1, block.timestamp);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }


    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _htkns,) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this));
        uint256 _amount = _htkns.mul(IHundred(hToken).exchangeRateStored());
        return _amount;
    }

    // returns rewards unharvested <--------------------------------------------------------------------NEEDS WORK
    function rewardsAvailable() public view returns (uint256 hTkns, uint256 rewardBal) {
        (,uint256 rewards) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this));
        return (,rewardBal);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "anon, you not the vault!"); //makes sure that only the vault can retire a strat
        (uint256 hTkns,) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this)); 
        ILQDR(LQDRFarm).withdrawAndHarvest(LQDRPid, hTkns, address(this));
        IHundred(hToken).redeem(hTkns);
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function LQDRpanic() public onlyOwner {
        pause();
        (uint256 hTkns,) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this)); 
        ILQDR(LQDRFarm).withdrawAndHarvest(LQDRPid, hTkns, address(this));
    }
    // pauses deposits and withdraws all funds from third party systems and returns funds to vault.
    function bigPanic() public onlyOwner {
        pause();
        (uint256 hTkns,) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this)); 
        ILQDR(LQDRFarm).withdrawAndHarvest(LQDRPid, hTkns, address(this));
        IHundred(hToken).redeem(hTkns);
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    function pause() public onlyOwner {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyOwner {
        _unpause();

        _giveAllowances();

        deposit();
    }

    // Sets the xCheeseRecipient address to recieve the BEETs rewards
    function setxCheeseRecipient(address _xCheeseRecipient) external onlyOwner {
        xCheeseRecipient = _xCheeseRecipient;
    }

    // place to reset where strategist fee goes.
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
    }
    // place to reset where performance fee goes.
    function setperFeeRecipient(address _perFeeRecipient) external onlyOwner {
        perFeeRecipient = _perFeeRecipient;
    }
    // Beets "the VAULT" rounter
    function setUnirouter(address _unirouter) external onlyOwner {
        unirouter = _unirouter;
    }
    // place to change the vault. very unlikely.
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }
    // to reduce deposit gas cost, this can be turned off.
    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(LQDRFarm, type(uint256).max);
        IERC20(HND).safeApprove(unirouter, type(uint256).max);
        IERC20(native).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(LQDRFarm, 0);
        IERC20(HND).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
    }
}