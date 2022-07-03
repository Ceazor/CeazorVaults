

// SPDX-License-Identifier: MIT


import "../../openzeppelin/IERC20.sol";
import "../../openzeppelin/Context.sol";
import "../../openzeppelin/Ownable.sol";
import "../../openzeppelin/SafeMath.sol";
import "../../openzeppelin/Address.sol";
import "../../openzeppelin/SafeERC20.sol";
import "../../openzeppelin/Math.sol";
import "../../beefy-contracts/interfaces/LPTokenWrapper.sol";



pragma solidity ^0.8.1;



contract ExtraCheese is LPTokenWrapper, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    IERC20 public rewardToken;
    uint256 public duration;

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

    constructor(address _stakedToken, address _rewardToken,  uint256 _duration)
        
        LPTokenWrapper(_stakedToken)
    {
        rewardToken = IERC20(_rewardToken);
        duration = _duration;
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
        require(amount > 0, "Cannot stake 0");
        super.stake(amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) override public updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
        getReward();
    }

        function getReward() public updateReward(msg.sender) {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function notifyRewardAmount()
        external
        onlyOwner
        updateReward(address(0))
    {
        require(periodFinish == 0, "!notified");

        uint256 reward = IERC20(rewardToken).balanceOf(address(this));

        require(reward != 0, "no rewards");
            
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(duration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(duration);
        }
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(duration);
        emit RewardAdded(reward);
    }

    function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        inCaseTokensGetStuck(_token, msg.sender, amount);
    }

    function inCaseTokensGetStuck(address _token, address _to, uint _amount) public onlyOwner {
        if (totalSupply() != 0) {
            require(_token != address(stakedToken), "!staked");
        }
        IERC20(_token).safeTransfer(_to, _amount);
    }
}