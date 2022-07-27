// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IUniswapV2Router01.sol";
import "../../interfaces/IBalancerVault.sol";
import "../../interfaces/IHundred.sol";
import "../../interfaces/ILQDR.sol";
import "../utils/FeeManager.sol";

contract HndBptToLQDRv2 is FeeManager, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

// essentials
    address public vault; 
    address public want;
    address public HND = address(0x10010078a54396F62c96dF8532dc2B4847d47ED3);     //HND token
    address public liHND = address(0xA147268f35Db4Ae3932eabe42AF16C36A8B89690);   //liHND
    address public LQDR = address(0x10b620b2dbAC4Faa7D7FFD71Da486f5D44cd86f9);    //LQDR token
    address public native = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);  //wftm but if pool doesnt use need to change this

//farm stuff
    address public LQDRFarm;
    uint256 public LQDRPid;
    address public bRouter = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);         // HND Swap route (The VAULT on Beets)
    bytes32 public LQDRSwapPoolId = bytes32(0x5e02ab5699549675a6d3beeb92a62782712d0509000200000000000000000138); //LQDR:wFTM 80/20 BPool
    bytes32 public HNDSwapPoolId = bytes32(0x843716e9386af1a26808d8e6ce3948d606ff115a00020000000000000000043a); //HND:wFTM 60/40 BPool 
    bytes32 public wantSwapPoolId;

    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit = bool(true);
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _vault,             // 0xd5Ab59A02E8610FCb9E7c7d863A9A2951dB33148 
        address _want,              // 0x8F6a658056378558fF88265f7c9444A0FB4DB4be HND:liHND BPT
        bytes32 _wantSwapPoolId,    // 0x8f6a658056378558ff88265f7c9444a0fb4db4be0002000000000000000002b8
        uint256 _LQDRPid,           // 39
        address _LQDRFarm           // 0x6e2ad6527901c9664f016466b8da1357a004db0f 
        
    ) {  
        vault = _vault;
        want = _want;
        wantSwapPoolId = _wantSwapPoolId;
        LQDRPid = _LQDRPid;
        LQDRFarm = _LQDRFarm;

        swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

        _giveAllowances();
    }

    function deposit() external {
        _deposit();
    }
    function beforeDeposit() external {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "only the vault anon!");  
            _harvest();
        }
    }
    
    function _deposit() internal whenNotPaused {
        uint256 _wantBal = IERC20(want).balanceOf(address(this));
        if (_wantBal > 0) {
            ILQDR(LQDRFarm).deposit(LQDRPid, _wantBal, (address(this)));
        }
    }
  
//takes the funds out of the farm and sends them to the vault.
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "ask the vault to withdraw ser!");  //makes sure only the vault can withdraw from the chef

        uint256 _wantBal = IERC20(want).balanceOf(address(this));

        if (_wantBal < _amount) {
            uint256 _TknNeed = _amount.sub(_wantBal);
            ILQDR(LQDRFarm).withdraw(LQDRPid, _TknNeed, (address(this)));
            _wantBal = IERC20(want).balanceOf(address(this));
        }

        if (_wantBal > _amount) {
            _wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = _wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            _wantBal = _wantBal.sub(withdrawalFeeAmount);
        }
        //return want to vault
        IERC20(want).safeTransfer(vault, _wantBal);

        emit Withdraw(balanceOf());
    }

    function harvest() external virtual {
        _harvest();
    }

// compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        ILQDR(LQDRFarm).harvest(LQDRPid, address(this));
        uint256 _LQDRBal = IERC20(LQDR).balanceOf(address(this));
        if (_LQDRBal > 0) {
            chargeFees(_LQDRBal);
            sendXCheese();
            uint256 _LQDRLeft = IERC20(LQDR).balanceOf(address(this));
            balancerSwap(LQDRSwapPoolId, LQDR, native, _LQDRLeft);
            uint256 _nativeBal = IERC20(native).balanceOf(address(this));
            balancerSwap(HNDSwapPoolId, native, HND, _nativeBal);
            uint256 _hndBal = IERC20(HND).balanceOf(address(this));
            balancerJoinWithHnd(_hndBal); 
            uint256 wantHarvested = IERC20(want).balanceOf(address(this));
            _deposit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf()); //tells everyone about the harvest 
        }
    }    

// performance fees
    function chargeFees(uint256 _LQDRBal) internal {
        uint256 _totalFees = _LQDRBal.mul(totalFee).div(1000);        
        if (_totalFees > 0) {
            balancerSwap(LQDRSwapPoolId, LQDR, native, _totalFees);
            uint256 _feesToSend = IERC20(native).balanceOf(address(this));
            uint256 strategistFee = _feesToSend.mul(STRATEGIST_FEE).div(MAX_FEE);
            uint256 perFeeAmount = _feesToSend.sub(strategistFee);
            IERC20(native).safeTransfer(strategist, strategistFee); 
            IERC20(native).safeTransfer(perFeeRecipient, perFeeAmount);  
        }
    }
//ceazor keeps a % of HND set by the xCheeseRate
    function sendXCheese() internal {
        uint256 forXCheese = IERC20(LQDR).balanceOf(address(this)).mul(xCheeseRate).div(100);
        if (forXCheese > 0) {
            IERC20(LQDR).safeTransfer(xCheeseRecipient, forXCheese);   // and send them to xCheese
        }
    }   

    function balancerSwap(bytes32 _poolId, address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(_poolId, swapKind, _tokenIn, _tokenOut, _amountIn, "");
        return IBalancerVault(bRouter).swap(singleSwap, funds, 1, block.timestamp);
    }
    function balancerJoinWithHnd(uint256 _amountIn) internal {    

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _amountIn;
        amounts[1] = 0; 
        bytes memory userData = abi.encode(1, amounts, 1);

        address[] memory tokens = new address[](2);
        tokens[0] = HND;
        tokens[1] = liHND;
        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(tokens, amounts, userData, false);
        IBalancerVault(bRouter).joinPool(wantSwapPoolId, address(this), address(this), request);
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
        (uint256 _amount,) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this));        
        return _amount;
    }

// returns rewards unharvested 
    function rewardsAvailable() public view returns (int256) {
        (,int256 rewardBal) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this));
        return (rewardBal);
    }

// called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "anon, you not the vault!"); //makes sure that only the vault can retire a strat
        (uint256 _Tkns, int256 _rewards) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this)); 
        ILQDR(LQDRFarm).withdraw(LQDRPid, _Tkns, address(this));
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
        
    }

// pauses deposits and withdraws all funds from third party systems.
    function LQDRpanic() public onlyOwner {
        pause();
        (uint256 _Tkns, int256 _rewards) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this)); 
        ILQDR(LQDRFarm).withdraw(LQDRPid, _Tkns, address(this));
    }
// pauses deposits and withdraws all funds from third party systems and returns funds to vault.
    function bigPanic() public onlyOwner {
        pause();
        (uint256 _Tkns, int256 _rewards) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this)); 
        ILQDR(LQDRFarm).withdraw(LQDRPid, _Tkns, address(this));
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

        _deposit();
    }

// to reduce deposit gas cost, this can be turned off.
    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }

//SWEEPERS
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        inCaseTokensGetStuck(_token, msg.sender, amount);
    }

// dev. can you do something?
    function inCaseTokensGetStuck(address _token, address _to, uint _amount) public onlyOwner {
        require(_token != address(want), "you gotta rescue your own deposits");
        IERC20(_token).safeTransfer(_to, _amount);
    }


//sets global allowances during deployment, and revokes when paused/panic'd.
    function _giveAllowances() internal {
        IERC20(want).safeApprove(LQDRFarm, type(uint256).max);
        IERC20(LQDR).safeApprove(bRouter, type(uint256).max);
        IERC20(HND).safeApprove(bRouter, type(uint256).max);
        IERC20(native).safeApprove(bRouter, type(uint256).max);

    }
    function _removeAllowances() internal {
        IERC20(want).safeApprove(LQDRFarm, 0);
        IERC20(LQDR).safeApprove(bRouter, 0);
        IERC20(HND).safeApprove(bRouter, 0);
        IERC20(native).safeApprove(bRouter, 0);
    }
}