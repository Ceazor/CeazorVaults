

// SPDX-License-Identifier: MIT


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "..//..//interfaces/LPTokenWrapper.sol";



pragma solidity ^0.8.11;



contract ExtraCheese is LPTokenWrapper, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 public rewardToken;
    uint256 public duration = 2628288; //Preset to 1month;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _stakedToken, address _rewardToken)
        
        LPTokenWrapper(_stakedToken)
    {
        rewardToken = IERC20(_rewardToken);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    
    function rewardPerToken() public view returns (uint256) {
        
        if (totalSupply() == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(totalSupply())
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            balanceOf(account)
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // stake visibility is public as overriding LPTokenWrapper's stake() function
    function stake(uint256 amount) override public updateReward(msg.sender) {
        require(amount > 0, "Go get you some ceazTKNS");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    // users withdraw their staked tokens.
    function withdraw(uint256 amount) override public updateReward(msg.sender) {
        require(amount > 0, "You've no tkns in here ser.");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    // Withdraw ALL and Claims rewards
    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

    // Claims rewards
    function getReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    // Calculates the reward rate based on the duration and tokens in the contract.
    function notifyRewardAmount()  
        external
        onlyOwner
        updateReward(address(0))
    {
        uint256 reward = IERC20(rewardToken).balanceOf(address(this));  // balance of tkns in contract now
        require(reward != 0, "you gotta fill'r up ser");                             // make sure not = 0
        rewardRate = reward.div(duration);                              

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(duration);
        emit RewardAdded(reward);
    }
    
    // Allows the owner to adjust the duration of the rewards. Reduce to increase APY
    // assuming there are tokens in the contract.
    function changeDuration(uint256 _newDuration) 
        external 
        onlyOwner 
        updateReward(address(0)) 
    {
        duration = _newDuration;
        newDurRewardAmount();
    }
    
    // This function is only called when changeDuration is called. 
    // It resets the reward rate.
    function newDurRewardAmount() internal {
        uint256 reward = IERC20(rewardToken).balanceOf(address(this));  
        require(reward != 0, "no rewards");                            
        rewardRate = reward.div(duration);                             
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(duration);
        emit RewardAdded(reward);
    }   

    // yup yup ser.
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        inCaseTokensGetStuck(_token, msg.sender, amount);
    }

    // dev. can you do something?
    function inCaseTokensGetStuck(address _token, address _to, uint _amount) public onlyOwner {
        if (totalSupply() != 0) {
            require(_token != address(stakedToken), "!staked");
        }
        IERC20(_token).safeTransfer(_to, _amount);
    }

    // added this to avoide import error statements. from @openzeppelin3.0/contracts/utils/Context.sol
    function _msgSender() internal view virtual override returns (address) {
        return msg.sender;
    }
}