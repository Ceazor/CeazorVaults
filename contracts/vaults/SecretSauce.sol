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

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

contract SecretSauceVault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct StratCandidate {
        address implementation;
        uint proposedTime;
    }

    StratCandidate public stratCandidate;
    address public strategy;
    uint256 public depositFee = 0;
    uint256 public constant PERCENT_DIVISOR = 10000;
    bool public initialized = false;
    uint public constructionTime;
    IERC20 public want; // USDC
    uint256 public approvalDelay = 3600;

    // SecretSnackSandwich NFT - gates deposit access
    IERC721 public constant sssNFT = IERC721(0x626Cb677412E672Ef115cC5Df85828746FBAd29A);

    // Budget per NFT held (10,000 USDC with 6 decimals)
    uint256 public budgetPerNFT = 10_000 * 1e6;
    mapping(uint256 => uint) public tknIdBudget;

    mapping(address => uint) public cumulativeDeposits;
    mapping(address => uint) public cumulativeWithdrawals;
    uint256 public totalDonated;

    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);
    event DepositsIncremented(address user, uint amount, uint total);
    event WithdrawalsIncremented(address user, uint amount, uint total);
    event Donated(address indexed donor, uint256 amount);
    event BudgetPerNFTUpdated(uint256 oldBudget, uint256 newBudget);

    constructor(
        address _want,
        string memory _name,
        string memory _symbol
    ) ERC20(string(_name), string(_symbol)) {
        want = IERC20(_want);
        constructionTime = block.timestamp;
    }
    ///////////////////////
    /// ADMIN Functions ///
    ///////////////////////
    //Connects the vault to its initial strategy. One use only.
    function initialize(address _strategy) public onlyOwner returns (bool) {
        require(!initialized, "Comm'on you alrdy did this!");
        strategy = _strategy;
        initialized = true;
        return true;
    }
    //Stages a new strategy for vault, applying it is delayed but approvalDelay
    function proposeStrat(address _implementation) public onlyOwner {
        stratCandidate = StratCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
         });
        emit NewStratCandidate(_implementation);
    }
    //retires old strat, pulling all funds, then applies candidate strat, delayed but approvalDelay
    function upgradeStrat() public onlyOwner {
        require(stratCandidate.implementation != address(0), "There is no candidate");
        require(stratCandidate.proposedTime.add(approvalDelay) < block.timestamp, "Delay has not passed");

        emit UpgradeStrat(stratCandidate.implementation);

        IStrategy(strategy).retireStrat();
        strategy = stratCandidate.implementation;
        stratCandidate.implementation = address(0);
        approvalDelay = 86400;    //sets delay to 24 hours

        earn();
    }
    //changes depositsfee, preset to 0
    function setDepositFee(uint256 fee) public onlyOwner {
        depositFee = fee;
    }
    function inCaseTokensGetStuck(address _want) external onlyOwner {
        require(_want != address(want), "!want");

        uint256 amount = IERC20(_want).balanceOf(address(this));
        IERC20(_want).safeTransfer(msg.sender, amount);
    }
    //////////////////////////////
    /// NFT Fetching Functions ///
    //////////////////////////////

///    mapping(uint256 => uint) public tknIdBudget;


    // Returns the USDC a user is allowed to deposit based on their NFT holdings
    function depositBudgetOf(address _tknID) public view returns (uint256) {
        uint256 nftBalance = tknIdBudget[_tknID];
        return nftBalance.mul(budgetPerNFT);
    }

    //////////////////////
    /// USER Functions ///
    //////////////////////
    function deposit(uint _amount, uint256 _tknID) public nonReentrant {
        require(_amount > 0, "Why are you depositing 0 tokens?");
        require(IERC721.ownerOf(_tknID) = msg.sender, "You don't own this NFT ID");

        // Check if NFT has deposited already
        if (tknIdBudget[_tknID] == 0){
            tknIdBudget = budgetPerNFT;
        }
        // Checks and adjusts current NFT budget
        uint256 budget = tknIdBudget[_tknID];
        require(budget < budgetPerNFT, "Must hold a SecretSnackSandwich NFT to deposit");
        require(_amount <= budget, "You cant deposit this much with this NFT");
        tknIdBudget[_tknID] += _amount;

        uint256 _pool = balance();
        uint256 _before = want.balanceOf(address(this));
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = want.balanceOf(address(this));
        _amount = _after.sub(_before);
        uint256 _amountAfterDeposit = (_amount.mul(PERCENT_DIVISOR.sub(depositFee))).div(PERCENT_DIVISOR);
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amountAfterDeposit;
        } else {
            shares = (_amountAfterDeposit.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);
        earn();
        incrementDeposits(_amount);
    }
    //withdraw function pulls funds from vault if able, or from farm.
    //this action forfeits rewards since last harvest
    function withdrawAll(uint256 _tknID) external {
        withdraw(balanceOf(msg.sender), _tknID);
    }
    function withdraw(uint256 _shares, uint256 _tknID) internal nonReentrant {
        require(_shares > 0, "you'v no deposits in this wallet");
        require(IERC721.ownerOf(_tknID) = msg.sender, "You don't own this NFT ID");

        uint256 r = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        tknIdBudget[_tknID] = budgetPerNFT;

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
    //////////////////////
    /// READ Functions ///
    //////////////////////
    // Total USDC held by vault + strategy
    function balance() public view returns (uint) {
        return want.balanceOf(address(this)).add(IStrategy(strategy).balanceOf());
    }

    // Tells you how much USDC each share token is worth
    function getPricePerFullShare() public view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : balance().mul(1e18).div(totalSupply());
    }
    ////////////////////////
    /// Public Functions ///
    ////////////////////////
    // Anyone can donate USDC to the vault.
    // No shares are minted - this increases the value of all existing shares.
    function donate(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Why are you donating 0 tokens?");
        uint256 _before = want.balanceOf(address(this));
        want.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _after = want.balanceOf(address(this));
        uint256 _actual = _after.sub(_before);
        totalDonated = totalDonated.add(_actual);
        earn();
        emit Donated(msg.sender, _actual);
    }
    // Sends idle USDC in vault to the strategy to put to work
    function earn() public {
        uint256 _wantbal = want.balanceOf(address(this));
        want.safeTransfer(strategy, _wantbal);
        IStrategy(strategy).deposit();
    }

    function incrementDeposits(uint _amount) internal returns (bool) {
      uint initial = cumulativeDeposits[tx.origin];
      uint newTotal = initial + _amount;
      cumulativeDeposits[tx.origin] = newTotal;
      budgetPerNFT[_tknID].sub(_amount);
      emit DepositsIncremented(tx.origin, _amount, newTotal);
      return true;
    }
    function incrementWithdrawals(uint _amount) internal returns (bool) {
      uint initial = cumulativeWithdrawals[tx.origin];
      uint newTotal = initial + _amount;
      cumulativeWithdrawals[tx.origin] = newTotal;
      budgetPerNFT[_tknID].add(_amount);
      emit WithdrawalsIncremented(tx.origin, _amount, newTotal);
      return true;
    }    
}