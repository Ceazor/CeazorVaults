// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;
pragma experimental ABIEncoderV2;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IBaseWeightedPool.sol";
import "../../interfaces/IBalancerGauge.sol";
import "../../interfaces/IBalancerGaugeHelper.sol";
import "../../interfaces/IBalancerVault.sol";
import "../../interfaces/ICeazor.sol";
import "../utils/FeeManager.sol";

contract IBBPTCompounderToBAL  is FeeManager, Pausable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

// Tokens used
    address public native = address(0x4200000000000000000000000000000000000006); //weth on op
    address public BAL = address(0xFE8B128bA8C78aabC59d4c64cEE7fF28e9379921);
    address public OP = address(0x4200000000000000000000000000000000000042); 
    address public want = address(0xeFb0D9F51EFd52d7589A9083A6d0CA4de416c249); //ibBPT "puff the magic dragon"
    address public reward = address(0x00a35FD824c717879BF370E70AC6868b95870Dfb); // IB
    address[] public lpTokens;
    
    address public vault; 

// Third party contracts
    address public bRouter = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);   // Beethoven Swap route (The VAULT) same on OP?
    address public chef = address(0x3672884a609bFBb008ad9252A544F52dF6451A03);      //this is called a gauge on OP
    address public helper = address(0x299dcDF14350999496204c141A0c20A29d71AF3E);     //just used for claim, pending()
    bytes32 public BALPoolId = bytes32(0xd6e5824b54f64ce6f1161210bc17eebffc77e031000100000000000000000006);        // only need this to sell beets. not at this point, viable
    bytes32 public OPPoolId = bytes32(0x39965c9dab5448482cf7e002f583c812ceb53046000100000000000000000003);
    bytes32 public rewardPoolId = bytes32(0xefb0d9f51efd52d7589a9083a6d0ca4de416c24900020000000000000000002c);
    bytes32 public wantPoolId = bytes32(0xefb0d9f51efd52d7589a9083a6d0ca4de416c24900020000000000000000002c);

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
            IBalancerGauge(chef).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "ask the vault to withdraw ser!");  

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IBalancerGauge(chef).withdraw(_amount.sub(wantBal), true);
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function harvest() external virtual {
        require(msg.sender == owner() || msg.sender == keeper, "only the key mastas can harvest"); 
        _harvest();
    }
    function _harvest() internal whenNotPaused {
        IBalancerGaugeHelper(helper).claimRewards(chef, address(this));
        uint256 BALBal = IERC20(BAL).balanceOf(address(this));   
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));   
        if (BALBal > 0 || rewardBal > 0) {
            chargeFees(BALBal, rewardBal);
            sendXCheese();
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            _deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf()); //tells everyone who did the harvest (they need be paid)
        }
    }

// performance fees
    function chargeFees(uint256 BALBal, uint256 rewardBal) internal {
        uint256 BALBalFees = BALBal.mul(totalFee).div(MULTIPLIER);
        if (BALBalFees > 0) {
            balancerSwap(BALPoolId, BAL, OP, BALBalFees);
            uint256 OPBal = IERC20(OP).balanceOf(address(this));
            balancerSwap(OPPoolId, OP, native, OPBal); 
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
        uint256 _BALBal = IERC20(BAL).balanceOf(address(this));
        uint256 _XCheeseCut = _BALBal.mul(xCheeseRate).div(100);
        if (_XCheeseCut > 0) {
            IERC20(BAL).safeTransfer(xCheeseRecipient, _XCheeseCut);          
        }
        uint256 _BALLeft = IERC20(BAL).balanceOf(address(this));
        if (_BALLeft > 0){
            balancerSwap(BALPoolId, BAL, OP, _BALLeft);
            uint256 OPBal = IERC20(OP).balanceOf(address(this));
            balancerSwap(OPPoolId, OP, native, OPBal);
        }
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
        amounts[1] = _nativeIn;
        amounts[0] = _rewardIn;
        bytes memory userData = abi.encode(1, amounts, 1);

        address[] memory tokens = new address[](2);
        tokens[1] = native;
        tokens[0] = reward;
        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(
            tokens, 
            amounts, 
            userData, 
            false);
        IBalancerVault(bRouter).joinPool(wantPoolId, address(this), address(this), request);
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
        uint256 _amount = IBalancerGauge(chef).balanceOf(address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "anon, you not the vault!"); //makes sure that only the vault can retire a strat
        _harvest();
        uint256 allWant = IBalancerGauge(chef).balanceOf(address(this));
        IBalancerGauge(chef).withdraw(allWant);
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyOwner {
        pause();
        uint256 allWant = IBalancerGauge(chef).balanceOf(address(this));
        IBalancerGauge(chef).withdraw(allWant);
            }
    // pauses deposits and withdraws all funds from third party systems and returns funds to vault.
    function bigPanic() public onlyOwner {
        pause();
        uint256 allWant = IBalancerGauge(chef).balanceOf(address(this));
        IBalancerGauge(chef).withdraw(allWant);
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

    // SWEEPERS yup yup ser
    function inCaseTokensGetStuck(address _token, address _to, uint _amount) public onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(chef, type(uint256).max);
        IERC20(BAL).safeApprove(bRouter, type(uint256).max);
        IERC20(reward).safeApprove(bRouter, type(uint256).max);        
        IERC20(native).safeApprove(bRouter, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(BAL).safeApprove(bRouter, 0);
        IERC20(reward).safeApprove(bRouter, 0);
        IERC20(native).safeApprove(bRouter, 0);
    }
}