// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;
pragma experimental ABIEncoderV2;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IBaseWeightedPool.sol";
import "../../interfaces/IBeethovenxChef.sol";
import "../../interfaces/IBalancerVault.sol";
import "../../interfaces/IBeetRewarder.sol";
import "../../interfaces/IBeethovenxFBeets.sol";
import "../../interfaces/ICeazor.sol";
import "../utils/FeeManager.sol";

contract Cre8rBPTCompounderToceazBeetsV3  is FeeManager, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

// Tokens used
    address public native = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83); //wftm but if pool doesnt use need to change this
    address public Beets = address(0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e); 
    address public want = address(0xbb4607beDE4610e80d35C15692eFcB7807A2d0A6); //CRE8R BPT
    address public reward = address(0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0); // CRE8R here
    address[] public lpTokens;
    
    address public vault;                                                                 

// Third party contracts
    address public bRouter = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);   // Beethoven Swap route (The VAULT)
    address public chef = address(0x8166994d9ebBe5829EC86Bd81258149B87faCfd3);      //this will be the same for all fantom pairs
    uint256 public chefPoolId = 39;                                                 //CRE8R Gauge PID
    address public rewarder = address(0x1098D1712592Bf4a3d73e5fD29Ae0da6554cd39f);  // this contract hold the CRE8R rewards
    bytes32 public beetsPoolId = 0xcde5a11a4acb4ee4c805352cec57e236bdbc3837000200000000000000000019;
    address public ceazFBeets = address(0x58E0ac1973F9d182058E6b63e7F4979bc333f493);
    address public fBEETS = address(0xfcef8a994209d6916EB2C86cDD2AFD60Aa6F54b1);
    address public beetsBPT = address(0xcdE5a11a4ACB4eE4c805352Cec57E236bdBC3837);
    bytes32 public rewardPoolId = bytes32(0xbb4607bede4610e80d35c15692efcb7807a2d0a6000200000000000000000140);
    bytes32 public wantPoolId = bytes32(0xbb4607bede4610e80d35c15692efcb7807a2d0a6000200000000000000000140);

    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit = bool(true);
    uint256 public lastHarvest;
    

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _vault             // 0xb06f1e0620f6b83c84a85E3c382442Cd1507F558 - ceazCRE8RF-Major
    ) {  
        vault = _vault;
        
        (lpTokens,,) = IBalancerVault(bRouter).getPoolTokens(wantPoolId);

        swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

        _giveAllowances();
    }
    function beforeDeposit() external {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "only the vault anon!");  
            _harvest();
        }
    }
    function deposit() external {
        _deposit();
    }

    function _deposit() internal whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IBeethovenxChef(chef).deposit(chefPoolId, wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "ask the vault to withdraw ser!");  //makes sure only the vault can withdraw from the chef

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IBeethovenxChef(chef).withdrawAndHarvest(chefPoolId, _amount.sub(wantBal), address(this));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function harvest() external virtual {
        _harvest();
    }
    function _harvest() internal whenNotPaused {
        IBeethovenxChef(chef).harvest(chefPoolId, address(this));
        uint256 BeetsBal = IERC20(Beets).balanceOf(address(this));   
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));   
        if (BeetsBal > 0 || rewardBal > 0) {
            chargeFees(BeetsBal, rewardBal);
            sendXCheese();
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            _deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf()); //tells everyone who did the harvest (they need be paid)
        }
    }

// performance fees
    function chargeFees(uint256 BeetsBal, uint256 rewardBal) internal {
        uint256 BeetsBalFees = BeetsBal.mul(totalFee).div(MULTIPLIER);
        if (BeetsBalFees > 0) {
            balancerSwap(beetsPoolId, Beets, native, BeetsBalFees);  
        }
        uint256 rewardBalFees = rewardBal.mul(totalFee).div(MULTIPLIER);
        if (rewardBalFees > 0) {
            balancerSwap(rewardPoolId, reward, native, rewardBalFees);  
        }
        uint256 _FeesInNativeBal = IERC20(native).balanceOf(address(this));

        uint256 strategistFee = _FeesInNativeBal.mul(stratFee).div(MULTIPLIER);
        IERC20(native).safeTransfer(strategist, strategistFee);

        uint256 perFeeAmount = _FeesInNativeBal.sub(strategistFee);
        IERC20(native).safeTransfer(perFeeRecipient, perFeeAmount);
        }

    function sendXCheese() internal{
        uint256 _beetsBal = IERC20(Beets).balanceOf(address(this));
        uint256 _XCheeseCut = _beetsBal.mul(xCheeseRate).div(100);
        if (_XCheeseCut > 0) {
            balancerJoinWithBeets(_XCheeseCut);
            wrapToFBeets();
            toCeazFBeets();
            uint256 ceazForXCheese = IERC20(ceazFBeets).balanceOf(address(this));
            IERC20(ceazFBeets).safeTransfer(xCheeseRecipient, ceazForXCheese);          
        }
        uint _beetsLeft = IERC20(Beets).balanceOf(address(this));
        balancerSwap(beetsPoolId, Beets, native, _beetsLeft);
    }

    function toCeazFBeets() internal{
        uint256 _fBEETSBal = IERC20(fBEETS).balanceOf(address(this));
        ICeazor(ceazFBeets).deposit(_fBEETSBal);
    }   
    function wrapToFBeets() internal{
        uint256 _BPTBal = IERC20(beetsBPT).balanceOf(address(this));
        IBeethovenxFBeets(fBEETS).enter(_BPTBal);
    }

// Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 _nativeIn = IERC20(native).balanceOf(address(this));
        uint256 _rewardIn = IERC20(reward).balanceOf(address(this));
        balancerJoinWithBoth(_rewardIn, _nativeIn);
    }

    function balancerSwap(bytes32 _poolId, address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(_poolId, swapKind, _tokenIn, _tokenOut, _amountIn, "");
        return IBalancerVault(bRouter).swap(singleSwap, funds, 1, block.timestamp);
    }
// tkns are ordered alphanumerically by contract addresses
    function balancerJoinWithBoth(uint256 _rewardIn, uint256 _nativeIn) internal {    

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = _nativeIn;
        amounts[1] = _rewardIn;
        bytes memory userData = abi.encode(1, amounts, 1);

        address[] memory tokens = new address[](2);
        tokens[0] = native;
        tokens[1] = reward;
        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(
            tokens, 
            amounts, 
            userData, 
            false);
        IBalancerVault(bRouter).joinPool(rewardPoolId, address(this), address(this), request);
    }
    function balancerJoinWithBeets(uint256 _amountIn) internal {    

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = _amountIn;
        bytes memory userData = abi.encode(1, amounts, 1);

        address[] memory tokens = new address[](2);
        tokens[0] = native;
        tokens[1] = Beets;
        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(
            tokens, 
            amounts, 
            userData, 
            false);
        IBalancerVault(bRouter).joinPool(beetsPoolId, address(this), address(this), request);
    }
// this is a generic automagic bJoin, but is not used here.
    function balancerJoin(bytes32 _poolId, address _tokenIn, uint256 _amountIn) internal {    

        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = lpTokens[i] == _tokenIn ? _amountIn : 0;
        }
        bytes memory userData = abi.encode(1, amounts, 1);   

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(
            lpTokens, 
            amounts, 
            userData, 
            false);
        IBalancerVault(bRouter).joinPool(_poolId, address(this), address(this), request);
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
        (uint256 _amount,) = IBeethovenxChef(chef).userInfo(chefPoolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256, uint256) {
        uint256 BeetsBal = IBeethovenxChef(chef).pendingBeets(chefPoolId, address(this));
        uint256 rewardBal = IBeetRewarder(rewarder).pendingToken(chefPoolId, address(this));
        return (BeetsBal, rewardBal);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "anon, you not the vault!"); //makes sure that only the vault can retire a strat

        IBeethovenxChef(chef).emergencyWithdraw(chefPoolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyOwner {
        pause();
        IBeethovenxChef(chef).emergencyWithdraw(chefPoolId, address(this));
    }
    // pauses deposits and withdraws all funds from third party systems and returns funds to vault.
    function bigPanic() public onlyOwner {
        pause();
        IBeethovenxChef(chef).emergencyWithdraw(chefPoolId, address(this));
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

    function setbRouter(address _bRouter) public onlyOwner {
        bRouter = _bRouter;
    }
    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }


    // dev. can you do something?
    function inCaseTokensGetStuck(address _token, address _to, uint _amount) public onlyOwner {
        require(_token != address(want), "you gotta rescue your own deposits");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(chef, type(uint256).max);
        IERC20(Beets).safeApprove(bRouter, type(uint256).max);
        IERC20(reward).safeApprove(bRouter, type(uint256).max);        
        IERC20(native).safeApprove(bRouter, type(uint256).max);
        IERC20(fBEETS).safeApprove(ceazFBeets, type(uint256).max);
        IERC20(beetsBPT).safeApprove(fBEETS, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(Beets).safeApprove(bRouter, 0);
        IERC20(reward).safeApprove(bRouter, 0);
        IERC20(native).safeApprove(bRouter, 0);
        IERC20(fBEETS).safeApprove(ceazFBeets, 0);
        IERC20(beetsBPT).safeApprove(fBEETS, 0);

    }
}