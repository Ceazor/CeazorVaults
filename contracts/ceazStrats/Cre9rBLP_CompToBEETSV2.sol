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
import "../strategies/FeeManager.sol";

contract BPTCompounderToBeetsV2  is FeeManager, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public want;
    address public Beets = address(0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e); //beets
    address public native = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83); //wftm but if pool doesnt use need to change this
    address public reward;
    address[] public lpTokens;
    address public bRouter = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);         // Beethoven Swap route (The VAULT)
    address public vault;                                                                   // The vault this strat is for
    address public perFeeRecipient;                                                         // Who gets the performance fee
    address public strategist;                                                              // Who gets the strategy fee
    address public xCheeseRecipient = address(0x699675204aFD7Ac2BB146d60e4E3Ddc243843519);  // preset to owner CHANGE ASAP

    // Third party contracts
    address public chef = address(0x8166994d9ebBe5829EC86Bd81258149B87faCfd3);              //hard coding this in to start
    uint256 public chefPoolId;
    address public rewarder;
    bytes32 public wantPoolId;
    bytes32 public beetsPoolId = 0xcde5a11a4acb4ee4c805352cec57e236bdbc3837000200000000000000000019;
    bytes32 public rewardPoolId;
    address public ceazFBeets = address(0x58E0ac1973F9d182058E6b63e7F4979bc333f493);
    address public fBEETS = address(0xfcef8a994209d6916EB2C86cDD2AFD60Aa6F54b1);
    address public beetsBPT = address(0xcdE5a11a4ACB4eE4c805352Cec57E236bdBC3837);


    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit = bool(true);
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _vault,             // 0xb06f1e0620f6b83c84a85E3c382442Cd1507F558 - ceazCRE8RF-Major
        address _strategist,        // 0x3c5Aac016EF2F178e8699D6208796A2D67557fe2 - ceazor
        address _perFeeRecipient,   // 0x3c5Aac016EF2F178e8699D6208796A2D67557fe2 - ceazor
        address _want,              // 0xbb4607beDE4610e80d35C15692eFcB7807A2d0A6 - CRE8RFMajor BPT
        address _reward,            // 0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0 - CRE8R here
        address _rewarder,          // 0x1098D1712592Bf4a3d73e5fD29Ae0da6554cd39f - CRE8R token farm
        uint256 _chefPoolId,        //39 CRE8R Gauge
        bytes32 _wantPoolId,        //0xbb4607bede4610e80d35c15692efcb7807a2d0a6000200000000000000000140
        bytes32 _rewardPoolId       //0xbb4607bede4610e80d35c15692efcb7807a2d0a6000200000000000000000140 - this assumes the reward might be different than the want


    ) {  
        vault = _vault;
        strategist = _strategist;
        perFeeRecipient = _perFeeRecipient;
        want = _want;
        reward = _reward;
        rewarder = _rewarder;
        chefPoolId = _chefPoolId;
        wantPoolId = _wantPoolId;
        rewardPoolId = _rewardPoolId;
        
        (lpTokens,,) = IBalancerVault(bRouter).getPoolTokens(wantPoolId);

        swapKind = IBalancerVault.SwapKind.GIVEN_IN;
        funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
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

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            wantBal = wantBal.sub(withdrawalFeeAmount);
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");  //makes sure the vault is the only one that can do quick preDeposit Harvest
            _harvest();
        }
    }

    function harvest() external virtual {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        IBeethovenxChef(chef).harvest(chefPoolId, address(this));
        uint256 BeetsBal = IERC20(Beets).balanceOf(address(this));   // beets harvest redundant as it calls in chargeFees
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));   // cre8r harvest redundant
        if (BeetsBal > 0 || rewardBal > 0) {
            chargeFees();
            _xCheese();
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf()); //tells everyone who did the harvest (they need be paid)
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 BeetsBalFees = IERC20(Beets).balanceOf(address(this)).mul(totalFee).div(1000);
        if (BeetsBalFees > 0) {
            balancerSwap(beetsPoolId, Beets, native, BeetsBalFees);  // swaps all the beets for wftm
        }

        uint256 rewardBalFees = IERC20(reward).balanceOf(address(this)).mul(totalFee).div(1000);
        if (rewardBalFees > 0) {
            balancerSwap(rewardPoolId, reward, native, rewardBalFees);  //swaps all the cre8r for wftm
        }
        // ceazor made total fee variable
        uint256 _FeesInNativeBal = IERC20(native).balanceOf(address(this)); //gets balance of wftm

        uint256 perFeeAmount = _FeesInNativeBal.mul(perFee).div(MAX_FEE);
        IERC20(native).safeTransfer(perFeeRecipient, perFeeAmount);  //calcs perFee and transfers

        uint256 strategistFee = _FeesInNativeBal.sub(perFeeAmount);
        IERC20(native).safeTransfer(strategist, strategistFee);      // calcs strategist fee and transfers

    }
    function _xCheese() internal{
        uint256 _beetsBal = IERC20(Beets).balanceOf(address(this));
        uint256 _XCheeseCut = _beetsBal.div(xCheeseRate);
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
        uint256 _nativeBal = IERC20(native).balanceOf(address(this));
        balancerSwap(rewardPoolId, native, reward, _nativeBal);
        uint256 _rewardBal = IERC20(reward).balanceOf(address(this));
        balancerJoin(wantPoolId, reward, _rewardBal);
    }

    function balancerSwap(bytes32 _poolId, address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(_poolId, swapKind, _tokenIn, _tokenOut, _amountIn, "");
        return IBalancerVault(bRouter).swap(singleSwap, funds, 1, block.timestamp);
    }

    function balancerJoin(bytes32 _poolId, address _tokenIn, uint256 _amountIn) internal {    

        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = lpTokens[i] == _tokenIn ? _amountIn : 0;
        }
        bytes memory userData = abi.encode(1, amounts, 1);   

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(lpTokens, amounts, userData, false);
        IBalancerVault(bRouter).joinPool(_poolId, address(this), address(this), request);
    }
    function balancerJoinWithBeets(uint256 _amountIn) internal {    

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = _amountIn;
        bytes memory userData = abi.encode(1, amounts, 1);

        address[] memory tokens = new address[](2);
        tokens[0] = native;
        tokens[1] = Beets;
        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(tokens, amounts, userData, false);
        IBalancerVault(bRouter).joinPool(beetsPoolId, address(this), address(this), request);
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

        deposit();
    }

    // different set functions
    function setStrategist(address _strategist) public onlyOwner {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
    }
    function setperFeeRecipient(address _perFeeRecipient) public onlyOwner {
        perFeeRecipient = _perFeeRecipient;
    }
    function setbRouter(address _bRouter) public onlyOwner {
        bRouter = _bRouter;
    }
    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }
    // this rate determines how much of the profit, post fees, is
    // is sent to xCheese farms.
    // this number is to be .div, so if set to 
    // 0 = nothing will be sent
    // 1 = ALL profts will be sent ???? can't be set to 1
    // 2 = half sent
    // 4 = 25 percent sent
    function setxCheeseRate(uint256 _rate) public onlyOwner {
        require(_rate != 1, "can't set this to 1"); 
        xCheeseRate = _rate;                                     
    }
    function setxCheeseRecipient(address _xCheeseRecipient) public onlyOwner {
        xCheeseRecipient = _xCheeseRecipient;
    }

        // yup yup ser.
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        inCaseTokensGetStuck(_token, msg.sender, amount);
    }

    // dev. can you do something?
    function inCaseTokensGetStuck(address _token, address _to, uint _amount) public onlyOwner {
        if (totalSupply() != 0) {
            require(_token != address(want), "you gotta rescue your own deposits");
        }
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