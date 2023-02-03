// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./EVCCoin.sol";


// MasterChef is the master of EVC. He can make EVC and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once EVC is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract EVCMasterChefL3 is Ownable, ReentrancyGuard {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLockedUp; // Reward locked up.
        uint256 nextHarvestUntil; // When can the user harvest again.
        //
        // We do some fancy math here. Basically, any point in time, the amount of KRs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accEVCPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accEVCPerShare` (and `lastRewardTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. KRs to distribute per second.
        uint256 lastRewardTime; // Last time KRs distribution occurs.
        uint256 accEVCPerShare; // Accumulated KRs per share, times 1e18. See below.
        uint16 depositFeeBP; // Deposit fee in basis points
        uint256 harvestInterval; // Harvest interval in seconds
    }

    // The EVC TOKEN!
    // EVCCoin public immutable evc;
    EVCCoin public immutable evc;
    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Dev address.
    address public devAddress;
    // Deposit Fee address
    address public feeAddress;

    // EVC tokens created per second.
    uint256 public evcPerSecond;
    // MAX TOKEN SUPPLY
    uint256 public constant MAX_SUPPLY = 50000 ether;
    // MAX POOL FEE
    uint256 public constant MAX_POOL_FEE = 400;
    // Max harvest interval: 2 days.
    uint256 public constant MAXIMUM_HARVEST_INTERVAL = 2 days;
    // Total locked up rewards
    uint256 public totalLockedUpRewards;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The timestamp when EVC mining starts.
    uint256 public startTime;
    // Maximum evcPerSecond
    uint256 public constant MAX_EMISSION_RATE = 0.1 ether;
    // Initial evcPerSecond
    uint256 public constant INITIAL_EMISSION_RATE = 0.02 ether;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(IERC20 => bool) public poolExistence;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 indexed evcPerSecond);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);
    event StartTimeChanged(uint256 oldStartTime, uint256 newStartTime);

    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    constructor(
        EVCCoin _evc,
        // EVCCoin _evc,
        address _devAddress,
        address _feeAddress,
        uint256 _startTime
    ) {
        evc = _evc;
        devAddress = _devAddress;
        feeAddress = _feeAddress;
        evcPerSecond = INITIAL_EMISSION_RATE;
        startTime = _startTime;
    }

    function poolLength() external view returns(uint256) {
        return poolInfo.length;
    }

    function blockTimestamp() external view returns(uint time) { // to assist with countdowns on site
        time = block.timestamp;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function addPool(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, uint256 _harvestInterval, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= MAX_POOL_FEE, "add: invalid deposit fee basis points");
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "add: invalid harvest interval");
        _lpToken.balanceOf(address(this));
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardTime: lastRewardTime,
            accEVCPerShare: 0,
            depositFeeBP: _depositFeeBP,
            harvestInterval: _harvestInterval
        }));
    }

    // Update startTime by the owner (added this to ensure that dev can delay startTime due to the congestion network). Only used if required. 
    function setStartTime(uint256 _newStartTime) external onlyOwner {
        require(startTime > block.timestamp, 'setStartTime: farm already started');
        require(_newStartTime > block.timestamp, 'setStartTime: new start time must be future time');
        uint256 _previousStartTime = startTime;
        startTime = _newStartTime;
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardTime = startTime;
        }
        emit StartTimeChanged(_previousStartTime, _newStartTime);
    }

    // Update the given pool's EVC allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, uint256 _harvestInterval, bool _withUpdate) external onlyOwner {
        require(_depositFeeBP <= MAX_POOL_FEE, "set: invalid deposit fee basis points");
        require(_harvestInterval <= MAXIMUM_HARVEST_INTERVAL, "set: invalid harvest interval");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].harvestInterval = _harvestInterval;
    }

    // Return reward multiplier over the given _from to _to timestamp.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns(uint256) {
        return _to.sub(_from);
    }

    // View function to see pending KRs on frontend.
    function pendingEVC(uint256 _pid, address _user) external view returns(uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accEVCPerShare = pool.accEVCPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 evcReward = multiplier.mul(evcPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accEVCPerShare = accEVCPerShare.add(evcReward.mul(1e18).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accEVCPerShare).div(1e18).sub(user.rewardDebt);
        return pending.add(user.rewardLockedUp);
    }

    // View function to see if user can harvest EVCs's.
    function canHarvest(uint256 _pid, address _user) public view returns(bool) {
        UserInfo storage user = userInfo[_pid][_user];
        return block.timestamp >= user.nextHarvestUntil;
    }

    // View function to see if user harvest until time.
    function getHarvestUntil(uint256 _pid, address _user) external view returns(uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.nextHarvestUntil;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 evcReward = multiplier.mul(evcPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
        if (evc.totalSupply() >= MAX_SUPPLY) {
            evcReward = 0;
        } else if (evc.totalSupply().add(evcReward.mul(11).div(10)) >= MAX_SUPPLY) {
            evcReward = (MAX_SUPPLY.sub(evc.totalSupply()).mul(10).div(11));
        }
        if (evcReward > 0) {
            evc.mint(devAddress, evcReward.div(10));
            evc.mint(address(this), evcReward);
            pool.accEVCPerShare = pool.accEVCPerShare.add(evcReward.mul(1e18).div(lpSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for EVC allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        payOrLockupPendingEVC(_pid);
        if (_amount > 0) {
            uint256 _balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            // for token that have transfer tax
            _amount = pool.lpToken.balanceOf(address(this)).sub(_balanceBefore);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accEVCPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        payOrLockupPendingEVC(_pid);
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(msg.sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accEVCPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function getPoolHarvestInterval(uint256 _pid) internal view returns(uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        return block.timestamp.add(pool.harvestInterval);
    }

    function isContract(address account) internal view returns(bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    // Pay or lockup pending evc.
    function payOrLockupPendingEVC(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.nextHarvestUntil == 0) {
            user.nextHarvestUntil = getPoolHarvestInterval(_pid);
        }
        uint256 pending = user.amount.mul(pool.accEVCPerShare).div(1e18).sub(user.rewardDebt);
        if (canHarvest(_pid, msg.sender)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);
                uint256 rewardsToLockup = totalRewards.div(2);
                uint256 rewardsToDistribute = totalRewards.sub(rewardsToLockup);
                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp).add(rewardsToLockup);
                user.rewardLockedUp = rewardsToLockup;
                user.nextHarvestUntil = getPoolHarvestInterval(_pid);
                // send rewards
                safeEVCTransfer(msg.sender, rewardsToDistribute);
            }
        } else if (pending > 0) {
            user.rewardLockedUp = user.rewardLockedUp.add(pending);
            totalLockedUpRewards = totalLockedUpRewards.add(pending);
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(msg.sender, user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = 0;
    }

    // Safe evc transfer function, just in case if rounding error causes pool to not have enough KRs.
    function safeEVCTransfer(address _to, uint256 _amount) internal {
        uint256 evcBal = evc.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > evcBal) {
            transferSuccess = evc.transfer(_to, evcBal);
        } else {
            transferSuccess = evc.transfer(_to, _amount);
        }
        require(transferSuccess, "safeEVCTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) external {
        require(_devAddress != address(0), "setDevAddress: setting devAddress to the zero address is forbidden");
        require(msg.sender == devAddress, "setDevAddress: caller is not devAddress");
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function setFeeAddress(address _feeAddress) external {
        require(_feeAddress != address(0), "setFeeAddress: setting feeAddress to the zero address is forbidden");
        require(msg.sender == feeAddress, "setFeeAddress: caller is not feeAddress");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _evcPerSecond) external onlyOwner {
        require(_evcPerSecond <= MAX_EMISSION_RATE, "updateEmissionRate: value higher than maximum");
        massUpdatePools();
        evcPerSecond = _evcPerSecond;
        emit UpdateEmissionRate(msg.sender, _evcPerSecond);
    }

}

