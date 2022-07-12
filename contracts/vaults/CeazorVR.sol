// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../../interfaces/IStrategy.sol";


pragma solidity ^0.8.11;

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract CeazorVaultR is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct StratCandidate {
        address implementation;
        uint proposedTime;
    }

    // The last proposed strategy to switch to.
    StratCandidate public stratCandidate;
    // The strategy currently in use by the vault.
    address public strategy;
    uint256 public depositFee = 0;
    uint256 public constant PERCENT_DIVISOR = 10000;
    bool public initialized = false;
    uint public constructionTime;
    IERC20 public want;
    uint256 public approvalDelay = 3600; //delay between strat changes, preset to 1 hour

    /**
     * + WEBSITE DISCLAIMER +
     * Im not a dev, don't put your tokens in here!.
     */

    /**
     * Mappings used to determine PnL denominated in LP tokens,
     * as well as keep a generalized history of a user's protocol usage.
     */
    mapping (address => uint) public cumulativeDeposits;
    mapping (address => uint) public cumulativeWithdrawals;

    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);
    event TermsAccepted(address user);

    event DepositsIncremented(address user, uint amount, uint total);
    event WithdrawalsIncremented(address user, uint amount, uint total);

    constructor (
        address _want,
        string memory _name,
        string memory _symbol
    ) public ERC20(
        string(_name),
        string(_symbol)
    ) {
        want = IERC20(_want);
        constructionTime = block.timestamp;       
    }
     
     
     //Connects the vault to its initial strategy. One use only.
    function initialize(address _strategy) public onlyOwner returns (bool) {
        require(!initialized, "Comm'on you alrdy did this!");
        strategy = _strategy;
        initialized = true;
        return true;
    }

    //It calculates the total underlying value of {token} held by the system.
    //vault  balance + strategy balance + farm balance
    function balance() public view returns (uint) {
        return want.balanceOf(address(this)).add(IStrategy(strategy).balanceOf());    }

    //tells you how much want each share token is worth
    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : balance().mul(1e18).div(totalSupply());
    }

    //deposits users tokens into the vault, then puts them too work in the farms
    function depositAll() external {
        deposit(want.balanceOf(msg.sender));
    }
    function deposit(uint _amount) public nonReentrant {
        require(_amount > 0, "please provide amount");
        uint256 _pool = balance();
        uint256 _before = want.balanceOf(address(this));
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = want.balanceOf(address(this));
        _amount = _after.sub(_before);
        uint256 _amountAfterDeposit = (_amount.mul(PERCENT_DIVISOR.sub(depositFee))).div(PERCENT_DIVISOR);
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amountAfterDeposit;
        }else {
            shares = (_amountAfterDeposit.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
        earn();
        incrementDeposits(_amount);
    }

    //Usually called by deposit() but puts money in vault to work
    function earn() public {
        uint256 _wantbal = want.balanceOf(address(this));
        want.safeTransfer(strategy, _wantbal);
        IStrategy(strategy).deposit();
    }

    //withdraw funcitions pull funds from vault if able, or from farm.
    //this action forfeits rewards since last harvest
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }
    function withdraw(uint256 _shares) public nonReentrant {
      require(_shares > 0, "you'v no deposits in this wallet");
        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        uint b = want.balanceOf(address(this));
        if (b < r) {
            uint _withdraw = r.sub(b);
            IStrategy(strategy).withdraw(_withdraw);
            uint _after = want.balanceOf(address(this));
            uint _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }
        want.safeTransfer(msg.sender, r);
        incrementWithdrawals(r);
    }

    //stages a new strategy for vault, applying it is delayed but approvalDelay
    function proposeStrat(address _implementation) public onlyOwner {
        stratCandidate = StratCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
         });
        emit NewStratCandidate(_implementation);
    }
    //changes depositsfee, preset to 0
    function setDepositFee(uint256 fee) public onlyOwner {
        depositFee = fee;
    }

    //retires old strat, pulling all funds, then applies candidate strat, delayed but approvalDelay
    function upgradeStrat() public onlyOwner {
        require(stratCandidate.implementation != address(0), "There is no candidate");
        require(stratCandidate.proposedTime.add(approvalDelay) < block.timestamp, "Delay has not passed");

        emit UpgradeStrat(stratCandidate.implementation);

        IStrategy(strategy).retireStrat();
        strategy = stratCandidate.implementation;
        stratCandidate.implementation = address(0);
        approvalDelay = 86400;                          //sets delay to 24 hours

        earn();
    }

    function incrementDeposits(uint _amount) internal returns (bool) {
      uint initial = cumulativeDeposits[tx.origin];
      uint newTotal = initial + _amount;
      cumulativeDeposits[tx.origin] = newTotal;
      emit DepositsIncremented(tx.origin, _amount, newTotal);
      return true;
    }

    function incrementWithdrawals(uint _amount) internal returns (bool) {
      uint initial = cumulativeWithdrawals[tx.origin];
      uint newTotal = initial + _amount;
      cumulativeWithdrawals[tx.origin] = newTotal;
      emit WithdrawalsIncremented(tx.origin, _amount, newTotal);
      return true;
    }    

    //allows for getting tokens out of the contract, but NOT want
    function inCaseTokensGetStuck(address _want) external onlyOwner {
        require(_want != address(want), "!want");

        uint256 amount = IERC20(_want).balanceOf(address(this));
        IERC20(_want).safeTransfer(msg.sender, amount);
    }
} 