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

    uint256 public constant PERCENT_DIVISOR = 10000;

    /**
    * @dev The strategy's initialization status. 
    */
    bool public initialized = false;
    uint public constructionTime;

    // The token the vault accepts and looks to maximize.
    IERC20 public want;
    // The minimum time it has to pass before a strat candidate can be approved. This is preset to 1 hour
    uint256 public approvalDelay = 3600;

    /**
     * + WEBSITE DISCLAIMER +
     * Im not a dev, don't put your tokens in here!.
     */

    /**
     * @dev simple mappings used to determine PnL denominated in LP tokens,
     * as well as keep a generalized history of a user's protocol usage.
     */
    mapping (address => uint) public cumulativeDeposits;
    mapping (address => uint) public cumulativeWithdrawals;

    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);
    event TermsAccepted(address user);

    event DepositsIncremented(address user, uint amount, uint total);
    event WithdrawalsIncremented(address user, uint amount, uint total);

    /**
     * @dev Sets the value of {token} to the token that the vault will
     * hold as underlying value. It initializes the vault's own 'ceazor' token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     * @param _want the token to maximize.
     * @param _name the name of the vault token.
     * @param _symbol the symbol of the vault token.
     */
    constructor (
        address _want,
        string memory _name,
        string memory _symbol,
    ) public ERC20(
        string(_name),
        string(_symbol)
    ) {
        want = IERC20(_want);
        constructionTime = block.timestamp;       
    }

    /**
     * @dev Connects the vault to its initial strategy. One use only.
     * @param _strategy the vault's initial strategy
     */

    function initialize(address _strategy) public onlyOwner returns (bool) {
        require(!initialized, "Comm'on you alrdy did this!");
        strategy = _strategy;
        initialized = true;
        return true;
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the vault contract balance, the strategy contract balance
     *  and the balance deployed in other contracts as part of the strategy.
     */
    function balance() public view returns (uint) {
        return want.balanceOf(address(this)).add(IStrategy(strategy).balanceOf());
    }

    /**
     * @dev Custom logic in here for how much the vault allows to be borrowed.
     * We return 100% of tokens for now. Under certain conditions we might
     * want to keep some of the system funds at hand in the vault, instead
     * of putting them to work.
     */
    function available() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : balance().mul(1e18).div(totalSupply());
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external {
        deposit(want.balanceOf(msg.sender));
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     * @notice the _before and _after variables are used to account properly for
     * 'burn-on-transaction' tokens.
     * @notice to ensure 'owner' can't sneak an implementation past the timelock,
     * it's set to true
     */
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

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the vault's deposit() function.
     */
    function earn() public {
        uint _bal = available();
        want.safeTransfer(strategy, _bal);
        IStrategy(strategy).deposit();
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
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

    /**
     * @dev Sets the candidate for the new strat to use with this vault.
     * @param _implementation The address of the candidate strategy.
     */
    function proposeStrat(address _implementation) public onlyOwner {
        stratCandidate = StratCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
         });
        emit NewStratCandidate(_implementation);
    }

    function updateDepositFee(uint256 fee) public onlyOwner {
        depositFee = fee;
    }

    /**
     * @dev It switches the active strat for the strat candidate. After upgrading, approvalDelay is set to 24 hours.
     */

    function upgradeStrat() public onlyOwner {
        require(stratCandidate.implementation != address(0), "There is no candidate");
        require(stratCandidate.proposedTime.add(approvalDelay) < block.timestamp, "Delay has not passed");

        emit UpgradeStrat(stratCandidate.implementation);

        IStrategy(strategy).retireStrat();
        strategy = stratCandidate.implementation;
        stratCandidate.implementation = address(0);
        approvalDelay = 86400;

        earn();
    }

    /*
    * @dev functions to increase user's cumulative deposits and withdrawals
    * @param _amount number of LP tokens being deposited/withdrawn
    */

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

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param _want address of the token to rescue.
     */
    function inCaseTokensGetStuck(address _want) external onlyOwner {
        require(_want != address(want), "!want");

        uint256 amount = IERC20(_want).balanceOf(address(this));
        IERC20(_want).safeTransfer(msg.sender, amount);
    }
} 