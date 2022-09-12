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
import "../../interfaces/ICeazor.sol";
import "../utils/FeeManager.sol";

contract hTokensToLQDR is FeeManager, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

// essentials
    // MIM = 0x82f0B8B456c1A451378467398982d4834b6829c1
    // hMIM = 0xa8cD5D59827514BCF343EC19F531ce1788Ea48f8
    // MIMFarm = 0xed566b089fc80df0e8d3e0ad3ad06116433bf4a7

    address public vault; 
    address public MIM = address(0x82f0B8B456c1A451378467398982d4834b6829c1);
    address public want = address(0xa8cD5D59827514BCF343EC19F531ce1788Ea48f8);
    address public HND = address(0x10010078a54396F62c96dF8532dc2B4847d47ED3);    
    address public native = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83); //wftm but if pool doesnt use need to change this

//farm stuff
    address public LQDRFarm = address(0xeD566B089Fc80Df0e8D3E0AD3aD06116433Bf4a7);
    uint256 public LQDRPid = 0;
    address public unirouter = address(0xF491e7B69E4244ad4002BC14e878a34207E38c29);       //this is coded to use Spookyswap   
    address public bRouter = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);         // HND Swap route (The VAULT on Beets)
    bytes32 public HNDSwapPoolId = bytes32(0x843716e9386af1a26808d8e6ce3948d606ff115a00020000000000000000043a); //HND:wFTM 60/40 BPool
//xCheese Stuff
    address public liHND = address(0xA147268f35Db4Ae3932eabe42AF16C36A8B89690);         //liHND
    address public liHNDBPT = address(0x8F6a658056378558fF88265f7c9444A0FB4DB4be);   
    address public ceazliHND = address(0xd5Ab59A02E8610FCb9E7c7d863A9A2951dB33148);
    bytes32 public liHNDPoolId = bytes32(0x8f6a658056378558ff88265f7c9444a0fb4db4be0002000000000000000002b8);

    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit = bool(true);
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _vault            
    
    ) {  
        vault = _vault;

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
// this converts the want to hTokens, then deposits the hTokens into Liquid Driver to earn rewards.
    function _deposit() internal whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            ILQDR(LQDRFarm).deposit(LQDRPid, _hTknBal, (address(this)));
        }
    }
  
//takes the funds out of the farm and sends them to the vault.
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "ask the vault to withdraw ser!");  //makes sure only the vault can withdraw from the chef

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) { 
            //withdraw htkn from lqdr but leaves behind rewards since last harvest
            ILQDR(LQDRFarm).withdraw(LQDRPid, _amount, (address(this)));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        //return want to vault
        IERC20(want).safeTransfer(vault, wantBal);
        emit Withdraw(balanceOf());
    }

    function harvest() external virtual {
        require(msg.sender == owner() || msg.sender == keeper, "only the key mastas can harvest");
        _harvest();
    }

// compounds earnings, charges fees, sends xCheese
    function _harvest() internal whenNotPaused {
        ILQDR(LQDRFarm).harvest(LQDRPid, address(this));
        uint256 _hndBal = IERC20(HND).balanceOf(address(this));        
        if (_hndBal > 0) {
            chargeFees(_hndBal);
            uint256 _hndLeft = IERC20(HND).balanceOf(address(this));
            balancerSwap(HNDSwapPoolId, HND, native, _hndLeft);
            uint256 _nativeBal = IERC20(native).balanceOf(address(this));
            _swapNativeForMIM(_nativeBal);
            uint256 _MIMBal - IERC20(MIM).balanceOf(address(this));
            IHundred(hToken).mint(_MIMBal);
            uint256 _hTknBal = IHundred(hToken).balanceOf(address(this)); 
            uint256 wantHarvested = balanceOfWant();
            _deposit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf()); 
        }
    }

    function chargeFees(uint256 _hndBal) internal {      
        uint256 _totalFees = _hndBal.mul(totalFee).div(MULTIPLIER);
        if (_totalFees > 0) {             
            balancerSwap(HNDSwapPoolId, HND, native, _totalFees);
            uint256 _feesToSend = IERC20(native).balanceOf(address(this));
            uint256 strategistFee = _feesToSend.mul(stratFee).div(MULTIPLIER);
            uint256 perFeeAmount = _feesToSend.sub(strategistFee);
            IERC20(native).safeTransfer(strategist, strategistFee); 
            IERC20(native).safeTransfer(perFeeRecipient, perFeeAmount);  
        }
    }

    function balancerSwap(bytes32 _poolId, address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(_poolId, swapKind, _tokenIn, _tokenOut, _amountIn, "");
        return IBalancerVault(bRouter).swap(singleSwap, funds, 1, block.timestamp);
    }

    function _swapNativeForMIM(uint256 _nativeBal) internal
        returns (uint256 _amountWant)
    {
        uint256[] memory amounts =
            IUniswapV2Router01(unirouter).swapExactTokensForTokens(
                _nativeBal,
                1,
                getTokenOutPath(address(native), address(want)),
                address(this),
                block.timestamp
            );
    }

    function getTokenOutPath(address _token_in, address _token_out)
        internal
        view
        returns (address[] memory _path)
    {
        bool is_weth = _token_in == address(native) || _token_out == address(native);
        _path = new address[](is_weth ? 2 : 3);
        _path[0] = _token_in;
        if (is_weth) {
            _path[1] = _token_out;
        } else {
            _path[1] = address(native);
            _path[2] = _token_out;
        }
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
        (uint256 hTkns,) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this)); 
        ILQDR(LQDRFarm).withdraw(LQDRPid, hTkns, address(this));
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function LQDRpanic() public onlyOwner {
        pause();
        (uint256 hTkns,) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this)); 
        ILQDR(LQDRFarm).withdraw(LQDRPid, hTkns, address(this));
    }
    // pauses deposits and withdraws all funds from third party systems and returns funds to vault.
    function bigPanic() public onlyOwner {
        pause();
        (uint256 hTkns,) = ILQDR(LQDRFarm).userInfo(LQDRPid, address(this)); 
        ILQDR(LQDRFarm).withdraw(LQDRPid, hTkns, address(this));
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
    function inCaseTokensGetStuck(address _token, address _to, uint _amount) public onlyOwner {
        require(_token != address(want), "you gotta rescue your own deposits");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    //sets global allowances during deployment, and revokes when paused/panic'd.
    function _giveAllowances() internal {
        IERC20(MIM).safeApprove(hToken, type(uint256).max);
        IERC20(want).safeApprove(LQDRFarm, type(uint256).max);
        IERC20(HND).safeApprove(bRouter, type(uint256).max);
        IERC20(liHNDBPT).safeApprove(ceazliHND, type(uint256).max);
        IERC20(native).safeApprove(bRouter, type(uint256).max);
        IERC20(native).safeApprove(unirouter, type(uint256).max);

    }
    function _removeAllowances() internal {
        IERC20(MIM).safeApprove(hToken, 0);
        IERC20(want).safeApprove(LQDRFarm, 0);
        IERC20(HND).safeApprove(bRouter, 0);
        IERC20(liHNDBPT).safeApprove(ceazliHND, 0);
        IERC20(native).safeApprove(bRouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
    }
}