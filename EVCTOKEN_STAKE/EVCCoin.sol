// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;



/**----------------------------

 /$$$$$$$$ /$$    /$$  /$$$$$$ 
| $$_____/| $$   | $$ /$$__  $$
| $$      | $$   | $$| $$  \__/
| $$$$$   |  $$ / $$/| $$      
| $$__/    \  $$ $$/ | $$      
| $$        \  $$$/  | $$    $$
| $$$$$$$$   \  $/   |  $$$$$$/
|________/    \_/     \______/ 

----------------------------**/



import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ReentrancyGuard.sol";


// EVCCoin.
contract EVCCoin is Ownable, ERC20, ERC20Burnable, ReentrancyGuard {

    // Rewards per hour. A fraction calculated as x/10.000.000 to get the percentage
    uint256 public rewardsPerHour = 285; // 0.00285%/h or 25% APR
    // Minimum amount to stake
    uint256 public minStake = 10000 * 10 ** decimals();
    // Compounding frequency limit in seconds
    uint256 public compoundFreq = 14400; //4 hours

    // Staker info
    struct Staker {
        // The deposited tokens of the Staker
        uint256 deposited;
        // Last time of details update for Deposit
        uint256 timeOfLastUpdate;
        // Calculated, but unclaimed rewards. These are calculated each time
        // a user writes to the contract.
        uint256 unclaimedRewards;
    }

    // Mapping of address to Staker info
    mapping(address => Staker) internal stakers;

    // Constructor function
    constructor() ERC20("EVCCoin", "EVC") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner() {
        _mint(_to, _amount);
    }

    // If address has no Staker struct, initiate one. If address already was a stake,
    // calculate the rewards and add them to unclaimedRewards, reset the last time of
    // deposit and then add _amount to the already deposited amount.
    // Burns the amount staked.
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount >= minStake, "Amount smaller than minimimum deposit");
        require(balanceOf(msg.sender) >= _amount, "Can't stake more than you own");
        if (stakers[msg.sender].deposited == 0) {
            stakers[msg.sender].deposited = _amount;
            stakers[msg.sender].timeOfLastUpdate = block.timestamp;
            stakers[msg.sender].unclaimedRewards = 0;
        } else {
            uint256 rewards = calculateRewards(msg.sender);
            stakers[msg.sender].unclaimedRewards += rewards;
            stakers[msg.sender].deposited += _amount;
            stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        }
        _burn(msg.sender, _amount);
    }

    // Compound the rewards and reset the last time of update for Deposit info
    function stakeRewards() external nonReentrant {
        require(stakers[msg.sender].deposited > 0, "You have no deposit");
        require(compoundRewardsTimer(msg.sender) == 0, "Tried to compound rewars too soon");
        uint256 rewards = calculateRewards(msg.sender) + stakers[msg.sender].unclaimedRewards;
        stakers[msg.sender].unclaimedRewards = 0;
        stakers[msg.sender].deposited += rewards;
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
    }

    // Mints rewards for msg.sender
    function claimRewards() external nonReentrant {
        uint256 rewards = calculateRewards(msg.sender) + stakers[msg.sender].unclaimedRewards;
        require(rewards > 0, "You have no rewards");
        stakers[msg.sender].unclaimedRewards = 0;
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        _mint(msg.sender, rewards);
    }

    // Withdraw specified amount of staked tokens
    function withdraw(uint256 _amount) external nonReentrant {
        require(stakers[msg.sender].deposited >= _amount, "Can't withdraw more than you have");
        uint256 _rewards = calculateRewards(msg.sender);
        stakers[msg.sender].deposited -= _amount;
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        stakers[msg.sender].unclaimedRewards = _rewards;
        _mint(msg.sender, _amount);
    }

    // Withdraw all stake and rewards and mints them to the msg.sender
    function withdrawAll() external nonReentrant {
        require(stakers[msg.sender].deposited > 0, "You have no deposit");
        uint256 _rewards = calculateRewards(msg.sender) + stakers[msg.sender].unclaimedRewards;
        uint256 _deposit = stakers[msg.sender].deposited;
        stakers[msg.sender].deposited = 0;
        stakers[msg.sender].timeOfLastUpdate = 0;
        uint256 _amount = _rewards + _deposit;
        _mint(msg.sender, _amount);
    }

    // Function useful for fron-end that returns user stake and rewards by address
    function getDepositInfo(address _user) public view returns(uint256 _stake, uint256 _rewards) {
        _stake = stakers[_user].deposited;
        _rewards = calculateRewards(_user) + stakers[msg.sender].unclaimedRewards;
        return (_stake, _rewards);
    }

    // Utility function that returns the timer for restaking rewards
    function compoundRewardsTimer(address _user) public view returns(uint256 _timer) {
        if (stakers[_user].timeOfLastUpdate + compoundFreq <= block.timestamp) {
            return 0;
        } else {
            return (stakers[_user].timeOfLastUpdate + compoundFreq) -
                block.timestamp;
        }
    }

    // Calculate the rewards since the last update on Deposit info
    function calculateRewards(address _staker) internal view returns(uint256 rewards) {
        return (((((block.timestamp - stakers[_staker].timeOfLastUpdate) *
            stakers[_staker].deposited) * rewardsPerHour) / 3600) / 10000000);
    }

    // Functions for modifying  staking mechanism variables:

    // Set rewards per hour as x/10.000.000 (Example: 100.000 = 1%)
    function setRewards(uint256 _rewardsPerHour) public onlyOwner {
        rewardsPerHour = _rewardsPerHour;
    }

    // Set the minimum amount for staking in wei
    function setMinStake(uint256 _minStake) public onlyOwner {
        minStake = _minStake;
    }

    // Set the minimum time that has to pass for a user to be able to restake rewards
    function setCompFreq(uint256 _compoundFreq) public onlyOwner {
        compoundFreq = _compoundFreq;
    }

}









// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;



/**----------------------------

 /$$$$$$$$ /$$    /$$  /$$$$$$ 
| $$_____/| $$   | $$ /$$__  $$
| $$      | $$   | $$| $$  \__/
| $$$$$   |  $$ / $$/| $$      
| $$__/    \  $$ $$/ | $$      
| $$        \  $$$/  | $$    $$
| $$$$$$$$   \  $/   |  $$$$$$/
|________/    \_/     \______/ 

----------------------------**/



import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ReentrancyGuard.sol";


// EVCCoin.
contract EVCCoin is Ownable, ERC20, ERC20Burnable, ReentrancyGuard {

    // Rewards per hour. A fraction calculated as x/10.000.000 to get the percentage
    uint256 public rewardsPerHour = 285; // 0.00285%/h or 25% APR
    // Minimum amount to stake
    uint256 public minStake = 10000 * 10 ** decimals();
    // Compounding frequency limit in seconds
    uint256 public compoundFreq = 14400; //4 hours

//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//
    uint256 public claimLock = 30 seconds;
//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//

    // Staker info
    struct Staker {
        // The deposited tokens of the Staker
        uint256 deposited;
        // Last time of details update for Deposit
        uint256 timeOfLastUpdate;
        // Calculated, but unclaimed rewards. These are calculated each time
        // a user writes to the contract.
        uint256 unclaimedRewards;

//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//
        uint256 depositAt;
        uint256 claimable;
//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//

    }

    // Mapping of address to Staker info
    mapping(address => Staker) internal stakers;

    // Constructor function
    constructor() ERC20("EVCCoin", "EVC") {
        _mint(msg.sender, 1000000000 * 10 ** decimals());
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner() {
        _mint(_to, _amount);
    }

    // If address has no Staker struct, initiate one. If address already was a stake,
    // calculate the rewards and add them to unclaimedRewards, reset the last time of
    // deposit and then add _amount to the already deposited amount.
    // Burns the amount staked.
    function deposit(uint256 _amount) external nonReentrant {
        require(_amount >= minStake, "Amount smaller than minimimum deposit");
        require(balanceOf(msg.sender) >= _amount, "Can't stake more than you own");
        if (stakers[msg.sender].deposited == 0) {
            stakers[msg.sender].deposited = _amount;
            stakers[msg.sender].timeOfLastUpdate = block.timestamp;
            stakers[msg.sender].unclaimedRewards = 0;
        } else {
            uint256 rewards = calculateRewards(msg.sender);
            stakers[msg.sender].unclaimedRewards += rewards;
            stakers[msg.sender].deposited += _amount;
            stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        }
        _burn(msg.sender, _amount);
    }

    // Compound the rewards and reset the last time of update for Deposit info
    function stakeRewards() external nonReentrant {
        require(stakers[msg.sender].deposited > 0, "You have no deposit");
        require(compoundRewardsTimer(msg.sender) == 0, "Tried to compound rewars too soon");
        uint256 rewards = calculateRewards(msg.sender) + stakers[msg.sender].unclaimedRewards;
        stakers[msg.sender].unclaimedRewards = 0;
        stakers[msg.sender].deposited += rewards;
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
    }

    // Mints rewards for msg.sender
    function claimRewards() external nonReentrant {
        uint256 rewards = calculateRewards(msg.sender) + stakers[msg.sender].unclaimedRewards;
        require(rewards > 0, "You have no rewards");
        stakers[msg.sender].unclaimedRewards = 0;
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        _mint(msg.sender, rewards);
    }

    // Withdraw specified amount of staked tokens
    function withdraw(uint256 _amount) external nonReentrant {
        require(stakers[msg.sender].deposited >= _amount, "Can't withdraw more than you have");
        uint256 _rewards = calculateRewards(msg.sender);
        stakers[msg.sender].deposited -= _amount;
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        stakers[msg.sender].unclaimedRewards = _rewards;
        _mint(msg.sender, _amount);
    }

    // Withdraw all stake and rewards and mints them to the msg.sender
    function withdrawAll() external nonReentrant {
        require(stakers[msg.sender].deposited > 0, "You have no deposit");
        uint256 _rewards = calculateRewards(msg.sender) + stakers[msg.sender].unclaimedRewards;
        uint256 _deposit = stakers[msg.sender].deposited;
        stakers[msg.sender].deposited = 0;
        stakers[msg.sender].timeOfLastUpdate = 0;
        uint256 _amount = _rewards + _deposit;
        _mint(msg.sender, _amount);
    }

    // Function useful for fron-end that returns user stake and rewards by address
    function getDepositInfo(address _user) public view returns(uint256 _stake, uint256 _rewards) {
        _stake = stakers[_user].deposited;
        _rewards = calculateRewards(_user) + stakers[msg.sender].unclaimedRewards;
        return (_stake, _rewards);
    }

    // Utility function that returns the timer for restaking rewards
    function compoundRewardsTimer(address _user) public view returns(uint256 _timer) {
        if (stakers[_user].timeOfLastUpdate + compoundFreq <= block.timestamp) {
            return 0;
        } else {
            return (stakers[_user].timeOfLastUpdate + compoundFreq) -
                block.timestamp;
        }
    }

    // Calculate the rewards since the last update on Deposit info
    function calculateRewards(address _staker) internal view returns(uint256 rewards) {
        return (((((block.timestamp - stakers[_staker].timeOfLastUpdate) *
            stakers[_staker].deposited) * rewardsPerHour) / 3600) / 10000000);
    }

    // Functions for modifying  staking mechanism variables:

    // Set rewards per hour as x/10.000.000 (Example: 100.000 = 1%)
    function setRewards(uint256 _rewardsPerHour) public onlyOwner {
        rewardsPerHour = _rewardsPerHour;
    }

    // Set the minimum amount for staking in wei
    function setMinStake(uint256 _minStake) public onlyOwner {
        minStake = _minStake;
    }

    // Set the minimum time that has to pass for a user to be able to restake rewards
    function setCompFreq(uint256 _compoundFreq) public onlyOwner {
        compoundFreq = _compoundFreq;
    }



//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//

    function stake(uint256 _amount) external nonReentrant {
        require(_amount >= minStake, "Amount smaller than minimimum deposit");
        require(balanceOf(msg.sender) >= _amount, "Can't stake more than you own");
        if (stakers[msg.sender].deposited == 0) {
            stakers[msg.sender].deposited = _amount;
            stakers[msg.sender].timeOfLastUpdate = block.timestamp;
            stakers[msg.sender].depositAt = block.timestamp;
            stakers[msg.sender].unclaimedRewards = 0;
        } else {
            uint256 rewards = calculateRewards(msg.sender);
            stakers[msg.sender].unclaimedRewards += rewards;
            stakers[msg.sender].deposited += _amount;
            stakers[msg.sender].timeOfLastUpdate = block.timestamp;
            stakers[msg.sender].depositAt = block.timestamp;
        }
        _burn(msg.sender, _amount);
    }

    function claimReward7() external nonReentrant {
        uint256 rewards = stakers[msg.sender].claimable;
        require(block.timestamp > stakers[msg.sender].depositAt + claimLock, "time remain to claim");
        require(rewards > 0, "You have no rewards");
        stakers[msg.sender].unclaimedRewards = 0;
        stakers[msg.sender].timeOfLastUpdate = block.timestamp;
        _mint(msg.sender, rewards);
        stakers[msg.sender].claimable = 0;
    }

    function unStakeFlex() external nonReentrant {
        require(stakers[msg.sender].deposited > 0, "You have no deposit");
        uint256 _rewards = calculateRewards(msg.sender) + stakers[msg.sender].unclaimedRewards;
        uint256 _deposit = stakers[msg.sender].deposited;
        stakers[msg.sender].deposited = 0;
        stakers[msg.sender].timeOfLastUpdate = 0;
        stakers[msg.sender].claimable = _rewards;
        uint256 _amount = _deposit;
        _mint(msg.sender, _amount);
    }

    function setclaimLock(uint256 _claimLock) public onlyOwner {
        claimLock = _claimLock;
    }

    function getDepositAt() public view returns(uint256) {
        return stakers[msg.sender].depositAt;
    }

    function getClaimTimer() public view returns(uint256) {
        uint256 depositAt = stakers[msg.sender].depositAt;
        return (depositAt + claimLock) - block.timestamp;
    }

//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//*---//



}












