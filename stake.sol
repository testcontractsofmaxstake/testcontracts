pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MultiTokenStaking
 * @dev A contract that allows staking of different ERC20 tokens across multiple pools,
 * distributing rewards in a single reward token.
 */
contract MultiTokenStaking is Ownable {
    // The ERC20 token used for rewards
    IERC20 public rewardToken;

    // Structure to store information about each staking pool
    struct PoolInfo {
        IERC20 token;           // The ERC20 token that can be staked in this pool
        uint256 rewardRate;     // Reward tokens distributed per second for this pool
        uint256 totalStaked;    // Total amount of tokens staked in this pool
        uint256 accRewardPerToken; // Accumulated reward per token, scaled by 1e18
        uint256 lastUpdateTime; // Last time the pool's rewards were updated
    }

    // Array of all staking pools
    PoolInfo[] public poolInfo;

    // User stakes: poolId => user address => staked amount
    mapping(uint256 => mapping(address => uint256)) public userStakes;

    // Reward per token paid to each user: poolId => user address => reward per token
    mapping(uint256 => mapping(address => uint256)) public userRewardPerTokenPaid;

    // Accumulated rewards claimable by each user in the reward token
    mapping(address => uint256) public rewards;

    // Events for tracking staking activities
    event Staked(address indexed user, uint256 poolId, uint256 amount);
    event Unstaked(address indexed user, uint256 poolId, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    /**
     * @dev Constructor sets the reward token address
     * @param _rewardToken Address of the ERC20 token used for rewards
     */
    constructor(address _rewardToken) {
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @dev Allows the owner to add a new staking pool
     * @param token Address of the ERC20 token to stake
     * @param rewardRate Reward tokens per second for this pool
     */
    function addPool(address token, uint256 rewardRate) external onlyOwner {
        poolInfo.push(PoolInfo({
            token: IERC20(token),
            rewardRate: rewardRate,
            totalStaked: 0,
            accRewardPerToken: 0,
            lastUpdateTime: block.timestamp
        }));
    }

    /**
     * @dev Updates the accumulated rewards for a pool
     * @param poolId Index of the pool to update
     */
    function updatePool(uint256 poolId) internal {
        PoolInfo storage pool = poolInfo[poolId];
        if (block.timestamp <= pool.lastUpdateTime) {
            return;
        }
        if (pool.totalStaked == 0) {
            pool.lastUpdateTime = block.timestamp;
            return;
        }
        uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
        uint256 reward = timeElapsed * pool.rewardRate;
        pool.accRewardPerToken += (reward * 1e18) / pool.totalStaked;
        pool.lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Allows a user to stake tokens in a specified pool
     * @param poolId Index of the pool
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 poolId, uint256 amount) external {
        require(amount > 0, "Cannot stake 0");
        require(poolId < poolInfo.length, "Invalid pool ID");

        PoolInfo storage pool = poolInfo[poolId];
        updatePool(poolId);

        // Calculate and accumulate any pending rewards
        if (userStakes[poolId][msg.sender] > 0) {
            uint256 pending = userStakes[poolId][msg.sender] * 
                             (pool.accRewardPerToken - userRewardPerTokenPaid[poolId][msg.sender]) / 1e18;
            rewards[msg.sender] += pending;
        }

        // Transfer tokens from user to contract
        pool.token.transferFrom(msg.sender, address(this), amount);

        // Update staking records
        userStakes[poolId][msg.sender] += amount;
        pool.totalStaked += amount;
        userRewardPerTokenPaid[poolId][msg.sender] = pool.accRewardPerToken;

        emit Staked(msg.sender, poolId, amount);
    }

    /**
     * @dev Allows a user to unstake tokens from a specified pool
     * @param poolId Index of the pool
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 poolId, uint256 amount) external {
        require(amount > 0, "Cannot unstake 0");
        require(poolId < poolInfo.length, "Invalid pool ID");

        PoolInfo storage pool = poolInfo[poolId];
        require(userStakes[poolId][msg.sender] >= amount, "Insufficient stake");

        updatePool(poolId);

        // Calculate and accumulate any pending rewards
        uint256 pending = userStakes[poolId][msg.sender] * 
                         (pool.accRewardPerToken - userRewardPerTokenPaid[poolId][msg.sender]) / 1e18;
        rewards[msg.sender] += pending;

        // Update staking records
        userStakes[poolId][msg.sender] -= amount;
        pool.totalStaked -= amount;

        // Transfer tokens back to user
        pool.token.transfer(msg.sender, amount);
        userRewardPerTokenPaid[poolId][msg.sender] = pool.accRewardPerToken;

        emit Unstaked(msg.sender, poolId, amount);
    }

    /**
     * @dev Allows a user to claim all accumulated rewards
     */
    function claimRewards() external {
        // Update rewards for all pools where the user has stakes
        for (uint256 poolId = 0; poolId < poolInfo.length; poolId++) {
            if (userStakes[poolId][msg.sender] > 0) {
                updatePool(poolId);
                uint256 pending = userStakes[poolId][msg.sender] * 
                                 (poolInfo[poolId].accRewardPerToken - userRewardPerTokenPaid[poolId][msg.sender]) / 1e18;
                rewards[msg.sender] += pending;
                userRewardPerTokenPaid[poolId][msg.sender] = poolInfo[poolId].accRewardPerToken;
            }
        }

        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards to claim");

        rewards[msg.sender] = 0;
        rewardToken.transfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, reward);
    }
}
