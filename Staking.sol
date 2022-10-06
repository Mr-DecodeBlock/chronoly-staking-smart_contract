// SPDX-License-Identifier: MIT
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/Math.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

pragma solidity ^0.8.0;

contract Staking is Ownable {
    using SafeMath for uint256;

    // uint8 public sixMonthAPR = 30;
    // uint8 public oneYearAPR = 60;
    // uint16 public threeYearAPR = 150;
    // uint[] public apr = [100, 330, 750, 1260, 1860];
    uint256 public totalStake;
    uint256 public totalRewards;

    enum StakingPeriod{ ONE_MONTH, THREE_MONTH, SIX_MONTH, NINE_MONTH, ONE_YEAR }

    struct stake {
        uint256 amount;
        StakingPeriod stakePeriod;
        uint timestamp;
    }

    address[] internal stakeholders;

    mapping(address => mapping(StakingPeriod => stake)) public stakes;
    mapping(StakingPeriod => uint) public apr;

    IERC20 public myToken;

    event TokenStaked(address indexed _from, uint amount, StakingPeriod plan, uint timestamp);
    event TokenUnstaked(address indexed _from, uint amount, StakingPeriod plan, uint timestamp);
    event RewardsTransferred(address indexed _to, uint amount, StakingPeriod plan, uint timestamp);

    constructor(address _myToken)
    { 
        myToken = IERC20(_myToken);
        apr[StakingPeriod.ONE_MONTH] = 100;
        apr[StakingPeriod.THREE_MONTH] = 330;
        apr[StakingPeriod.SIX_MONTH] = 750;
        apr[StakingPeriod.NINE_MONTH] = 1260;
        apr[StakingPeriod.ONE_YEAR] = 1860;
    }

    // ---------- STAKES ----------

    function createStake(uint256 _stake, StakingPeriod _stakePeriod) public {
        require(_stake > 0, "stake value should not be zero");
        require(myToken.transferFrom(msg.sender, address(this), _stake), "Token Transfer Failed");
        if(stakes[msg.sender][_stakePeriod].amount == 0) {
            addStakeholder(msg.sender);
            stakes[msg.sender][_stakePeriod] = stake(_stake, _stakePeriod, block.timestamp);
            totalStake = totalStake.add(_stake);
        } else {
            stake memory tempStake = stakes[msg.sender][_stakePeriod];
            tempStake.amount = tempStake.amount.add(_stake);
            tempStake.timestamp = block.timestamp;
            stakes[msg.sender][_stakePeriod] = tempStake;
            totalStake = totalStake.add(_stake);
        }
        emit TokenStaked(msg.sender, _stake, _stakePeriod, block.timestamp);
    }

    function unStake(uint256 _stake, StakingPeriod _stakePeriod) public {
        require(_stake > 0, "stake value should not be zero");
        stake memory tempStake = stakes[msg.sender][_stakePeriod];
        require(validateStakingPeriod(tempStake), "Staking period is not expired");
        require(_stake <= tempStake.amount, "Invalid Stake Amount");
        uint256 _investorReward = getDailyRewards(_stakePeriod);
        tempStake.amount = tempStake.amount.sub(_stake);
        stakes[msg.sender][_stakePeriod] = tempStake;
        totalStake = totalStake.sub(_stake);
        totalRewards = totalRewards.add(_investorReward);
        //uint256 tokensToBeTransfer = _stake.add(_investorReward);
        if(stakes[msg.sender][_stakePeriod].amount == 0) removeStakeholder(msg.sender);
        myToken.transfer(msg.sender, _stake);
        myToken.transferFrom(owner(), msg.sender, _investorReward);
        emit TokenUnstaked(msg.sender, _stake, _stakePeriod, block.timestamp);
        emit RewardsTransferred(msg.sender, _investorReward, _stakePeriod, block.timestamp);
    }

    function getInvestorRewards(uint256 _unstakeAmount, stake memory _investor) internal view returns (uint256) {
        // uint256 investorStakingPeriod = getStakingPeriodInNumbers(_investor);
        // uint APY = investorStakingPeriod == 26 weeks ? sixMonthAPR : investorStakingPeriod == 52 weeks ? oneYearAPR : investorStakingPeriod == 156 weeks ? threeYearAPR : 0;
        return _unstakeAmount.mul(apr[_investor.stakePeriod]).div(100).div(100);
    } 

    function validateStakingPeriod(stake memory _investor) internal view returns(bool) {
        uint256 stakingTimeStamp = _investor.timestamp + getStakingPeriodInNumbers(_investor);
        return true; // change it to block.timestamp >= stakingTimeStamp; while deploying
    } 

    function getStakingPeriodInNumbers(stake memory _investor) internal pure returns (uint256){
        return _investor.stakePeriod == StakingPeriod.ONE_MONTH ? 4 weeks : _investor.stakePeriod == StakingPeriod.THREE_MONTH ? 12 weeks : _investor.stakePeriod == StakingPeriod.SIX_MONTH ? 24 weeks : _investor.stakePeriod == StakingPeriod.NINE_MONTH ? 36 weeks : _investor.stakePeriod == StakingPeriod.ONE_YEAR ? 48 weeks : 0; 
    }

    function stakeOf(address _stakeholder, StakingPeriod _stakePeriod)
        public
        view
        returns(uint256)
    {
        return stakes[_stakeholder][_stakePeriod].amount;
    }

    function stakingPeriodOf(address _stakeholder, StakingPeriod _stakePeriod) public view returns (StakingPeriod) {
        return stakes[_stakeholder][_stakePeriod].stakePeriod;
    }

    function getDailyRewards(StakingPeriod _stakePeriod) public view returns (uint256) {
        stake memory tempStake = stakes[msg.sender][_stakePeriod];
        uint256 total_rewards = getInvestorRewards(tempStake.amount, tempStake);
        uint256 noOfDays = (block.timestamp - tempStake.timestamp).div(60).div(60).div(24);
        noOfDays = (noOfDays < 1) ? 1 : noOfDays;
       // uint256 stakingPeriodInDays =  getStakingPeriodInNumbers(tempStake).div(60).div(60).div(24);
        return total_rewards.div(364).mul(noOfDays);
    }

    // ---------- STAKEHOLDERS ----------

    function isStakeholder(address _address)
        internal
        view
        returns(bool, uint256)
    {
        for (uint256 s = 0; s < stakeholders.length; s += 1){
            if (_address == stakeholders[s]) return (true, s);
        }
        return (false, 0);
    }

   
    function addStakeholder(address _stakeholder)
        internal
    {
        (bool _isStakeholder, ) = isStakeholder(_stakeholder);
        if(!_isStakeholder) stakeholders.push(_stakeholder);
    }

    
    function removeStakeholder(address _stakeholder)
        internal
    {
        (bool _isStakeholder, uint256 s) = isStakeholder(_stakeholder);
        if(_isStakeholder){
            stakeholders[s] = stakeholders[stakeholders.length - 1];
            stakeholders.pop();
        } 
    }
    // ---------- REWARDS ----------

    
    function getTotalRewards()
        public
        view
        returns(uint256)
    {
        return totalRewards;
    }

    // ---- Staking APY  setters ---- 

    function setApyPercentage(uint8 _percentage, StakingPeriod _stakePeriod) public onlyOwner {
        uint percentage = _percentage * 100;
        apr[_stakePeriod] = percentage;
    }

    function remainingTokens() public view returns (uint256) {
        return Math.min(myToken.balanceOf(owner()), myToken.allowance(owner(), address(this)));
    }

}