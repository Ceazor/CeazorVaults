// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;
pragma experimental ABIEncoderV2;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../../interfaces/IOla.sol";
import "../../interfaces/IUniswapV2Router01.sol";
import "../utils/FeeManager.sol";
import "../utils/GasThrottler.sol";

contract Cre8rSLP_Comp  is FeeManager, Pausable, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public vault; 
    address public want = address(0x459e7c947E04d73687e786E4A48815005dFBd49A); //CRE8R SLP
    address public Spirit = address(0x5Cc61A78F164885776AA610fb0FE1257df78E59B); 
    address public native = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83); 
    address public CRE8R = address(0x2aD402655243203fcfa7dCB62F8A08cc2BA88ae0);
    
    // external contracts    
    address public olaBoostFarm = address(0xbbB192f66256002C96Dae28770b2622DB41d56Cc);
    address public handler = address(0x5EC162968b30cCfCDe614185ef340D585958AE23);
    uint256 public chefPoolId = 64;
    address public unirouter = address(0x16327E3FbDaCA3bcF7E38F5Af2599D2DDc33aE52);
    address public keeper = address(0x6EDe1597c05A0ca77031cBA43Ab887ccf24cd7e8); //preset to Gelato on Fantom

    bool public harvestOnDeposit = bool(true);
    uint256 public lastHarvest;    

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);

    constructor(
        address _vault             // ????????????????????????????????????????/
    ) {  
        vault = _vault;

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
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IOla(olaBoostFarm).deposit(wantBal); 
            emit Deposit(balanceOf());
        }
    }
    
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "ask the vault to withdraw ser!");  
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IOla(olaBoostFarm).withdraw(_amount.sub(wantBal));
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

    function harvest() external gasThrottle virtual {
        require(msg.sender == owner() || msg.sender == keeper, "only the key mastas can harvest");
        _harvest();
    }
    function _harvest() internal whenNotPaused {
        IOla(olaBoostFarm).getReward(handler, getParams());  
        uint256 _SpiritBal = IERC20(Spirit).balanceOf(address(this));
        if (_SpiritBal > 0) {
            chargeFees(_SpiritBal);
            sendXCheese();
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            _deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }
    function chargeFees(uint256 _Spiritbal) internal {
        uint256 _totalFees = _Spiritbal.mul(totalFee).div(1000);
        if (_totalFees > 0) {
            IUniswapV2Router01(unirouter).swapExactTokensForTokens(
                _totalFees,
                0,
                getTokenOutPath(Spirit, native),
                address(this),
                block.timestamp);
            uint256 _fees = IERC20(native).balanceOf(address(this));    
            uint256 strategistFee = _fees.mul(STRATEGIST_FEE).div(MAX_FEE);
            uint256 perFeeAmount = _fees.sub(strategistFee);
            IERC20(native).safeTransfer(strategist, strategistFee); 
            IERC20(native).safeTransfer(perFeeRecipient, perFeeAmount);  
        }
    }
    function sendXCheese() internal{ //<-----------------------------------------this not going to ceazToken yet
        uint256 _SpiritBal = IERC20(Spirit).balanceOf(address(this));
        uint256 _XCheeseCut = _SpiritBal.mul(xCheeseRate).div(100);
        if (_XCheeseCut > 0) {
            IERC20(Spirit).safeTransfer(xCheeseRecipient, _XCheeseCut);          
        }
    }
    function addLiquidity() internal { 
        uint256 _SpiritBal = IERC20(Spirit).balanceOf(address(this));
        IUniswapV2Router01(unirouter).swapExactTokensForTokens(
            _SpiritBal, 
            0, 
            getTokenOutPath(Spirit, native), 
            address(this), 
            block.timestamp);

        uint256 _half = IERC20(native).balanceOf(address(this)).div(2); 
        IUniswapV2Router01(unirouter).swapExactTokensForTokens(   //<<--------------this gets LOCKED error
            _half, 
            1, 
            getTokenOutPath(native, CRE8R), 
            address(this), 
            1691443884);
        uint256 nativeBal = IERC20(native).balanceOf(address(this)); 
        uint256 cre8rBal = IERC20(CRE8R).balanceOf(address(this));
        IUniswapV2Router01(unirouter).addLiquidity(
            CRE8R,  
            native,
            cre8rBal,
            nativeBal, 
            1,
            1,
            address(this), 
            block.timestamp);
    }
    function getParams()
        internal
        view
        returns (bytes32[] memory params)
    {
        params = new bytes32[](2);
        params[0] = bytes32(chefPoolId);
        params[1] = 0;
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
        uint256 _amount = IOla(olaBoostFarm).balanceOf(address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256 rewardBal) { 
        rewardBal = IOla(olaBoostFarm).earnedCurrentMinusFee(address(this));
        return (rewardBal);
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "anon, you not the vault!"); 
        IOla(olaBoostFarm).withdrawAll(); 
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyOwner {
        pause();
        IOla(olaBoostFarm).withdrawAll(); 
    }
    // pauses deposits and withdraws all funds from third party systems and returns funds to vault.
    function bigPanic() public onlyOwner {
        pause();
        IOla(olaBoostFarm).withdrawAll(); 
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
    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyOwner {
        harvestOnDeposit = _harvestOnDeposit;
    }

    // SWEEPERS yup yup ser
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        inCaseTokensGetStuck(_token, msg.sender, amount);
    }

    // dev. can you do something?
    function inCaseTokensGetStuck(address _token, address _to, uint _amount) public onlyOwner {
        require(_token != address(want), "you gotta rescue your own deposits");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(olaBoostFarm, type(uint256).max);
        IERC20(Spirit).safeApprove(unirouter, type(uint256).max);
        IERC20(CRE8R).safeApprove(unirouter, type(uint256).max);        
        IERC20(native).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(olaBoostFarm, 0);
        IERC20(Spirit).safeApprove(unirouter, 0);
        IERC20(CRE8R).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, 0);
    }
}