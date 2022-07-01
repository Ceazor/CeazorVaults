// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../../openzepplin/ERC20.sol";
import "../../openzepplin/SafeERC20.sol";
import "../../openzepplin/SafeMath.sol";
import "../../openzepplin/Pauseable.sol";

import "../interfaces/IBeethovenxChef.sol";
import "../interfaces/IBalancerVault.sol";
import "../interfaces/IBeetRewarder.sol";
import "../strategies/StratManager.sol";
import "../strategies/FeeManager.sol";

contract StrategyBeethovenxDual is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public want;
    address public output = address(0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e); //beets
    address public native = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83); //wftm
    address public input;
    address public reward;
    address[] public lpTokens;

    // Third party contracts
    address public chef;
    uint256 public chefPoolId;
    address public rewarder;
    bytes32 public wantPoolId;
    bytes32 public nativeSwapPoolId;
    bytes32 public inputSwapPoolId;
    bytes32 public rewardSwapPoolId;

    IBalancerVault.SwapKind public swapKind;
    IBalancerVault.FundManagement public funds;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        bytes32[] memory _balancerPoolIds,
        uint256 _chefPoolId,        //39 CRE8R Gauge
        address _chef,              // 0x8166994d9ebBe5829EC86Bd81258149B87faCfd3 - BeethovenxMasterChef
        address _input,             // 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83 - wFTM
        address _vault,             // ?????????????????????????????????????????? - ceazCRE8RF-Major
        address _unirouter,         // 0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce - vault ?beets swap?
        // address _keeper,
        address _strategist,        // 0x3c5Aac016EF2F178e8699D6208796A2D67557fe2 - ceazor
        address _perFeeRecipient  // 0x3c5Aac016EF2F178e8699D6208796A2D67557fe2 - ceazor for now will be xCheese
    ) StratManager( _strategist, _unirouter, _vault, _perFeeRecipient) public {  //removed keeper
        wantPoolId = _balancerPoolIds[0];
        nativeSwapPoolId = _balancerPoolIds[1];
        inputSwapPoolId = _balancerPoolIds[2];
        rewardSwapPoolId = _balancerPoolIds[3];
        chefPoolId = _chefPoolId;
        chef = _chef;

        (want,) = IBalancerVault(unirouter).getPool(wantPoolId);
        rewarder = IBeethovenxChef(chef).rewarder(chefPoolId);
        input = _input;
        reward = IBeetRewarder(rewarder).rewardToken();

        (lpTokens,,) = IBalancerVault(unirouter).getPoolTokens(wantPoolId);
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
        require(msg.sender == vault, "!vault");

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

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IBeethovenxChef(chef).harvest(chefPoolId, address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));   // beets harvest
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));   // cre8r harvest
        if (outputBal > 0 || rewardBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            balancerSwap(nativeSwapPoolId, output, native, outputBal);  // swaps all the beets for wftm
        }

        uint256 rewardBal = IERC20(reward).balanceOf(address(this));
        if (rewardBal > 0) {
            balancerSwap(rewardSwapPoolId, reward, native, rewardBal);  //swaps all the cre8r for wftm
        }

        uint256 nativeBal = IERC20(native).balanceOf(address(this)).mul(45).div(1000); //assigns balance of wftm

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE); 
        IERC20(native).safeTransfer(callperFeeRecipient, callFeeAmount); //calcs callfee and transfers

        uint256 perFeeAmount = nativeBal.mul(perFee).div(MAX_FEE);
        IERC20(native).safeTransfer(perFeeRecipient, perFeeAmount);  //calcs perFee and transfers

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);      // calcs strategist fee and transfers

        uint256 forXCheese = IERC20(native).balanceOf(address(this));
        if (forXCheese > 0) {
            balancerSwap(nativeSwapPoolId, output, native, (forXCheese).div(2));    // swaps half the remaining wtfm for Beets 
            IERC20(native).safeTransfer(xCheeseRecipient, forXCheese);              // and send them to xCheese
        }
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        if (input != native) {
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            balancerSwap(inputSwapPoolId, output, input, outputBal);
        }

        uint256 inputBal = IERC20(input).balanceOf(address(this));
        balancerJoin(wantPoolId, input, inputBal);
    }

    function balancerSwap(bytes32 _poolId, address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(_poolId, swapKind, _tokenIn, _tokenOut, _amountIn, "");
        return IBalancerVault(unirouter).swap(singleSwap, funds, 1, now);
    }

    function balancerJoin(bytes32 _poolId, address _tokenIn, uint256 _amountIn) internal {
        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = lpTokens[i] == _tokenIn ? _amountIn : 0;
        }
        bytes memory userData = abi.encode(1, amounts, 1);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(lpTokens, amounts, userData, false);
        IBalancerVault(unirouter).joinPool(_poolId, address(this), address(this), request);
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
        uint256 outputBal = IBeethovenxChef(chef).pendingBeets(chefPoolId, address(this));
        uint256 rewardBal = IBeetRewarder(rewarder).pendingToken(chefPoolId, address(this));
        return (outputBal, rewardBal);
    }

    // native reward amount for calling harvest
    function callReward() public returns (uint256) {
        (uint256 outputBal, uint256 rewardBal) = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            nativeOut = balancerSwap(nativeSwapPoolId, output, native, outputBal);
        }
        if (rewardBal > 0) {
            nativeOut += balancerSwap(rewardSwapPoolId, reward, native, rewardBal);
        }

        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IBeethovenxChef(chef).emergencyWithdraw(chefPoolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IBeethovenxChef(chef).emergencyWithdraw(chefPoolId, address(this));
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(chef, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(reward).safeApprove(unirouter, uint256(-1));

        IERC20(input).safeApprove(unirouter, 0);
        IERC20(input).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(reward).safeApprove(unirouter, 0);
        IERC20(input).safeApprove(unirouter, 0);
    }
}