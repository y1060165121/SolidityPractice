// SPDX-License-Identifier: GPL-3.0-only
// This is a PoC to use the staking precompile wrapper as a Solidity developer.
pragma solidity >=0.8.0;

import "./StakingInterface.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract DelegationDAO is AccessControl {

    using SafeMath for uint256;

    // Role definition for contract members
    bytes32 public constant MEMBER = keccak256("MEMBER");

    // Possible states for the DAO to be in:
    // COLLECTING: the DAO is collecting funds before creating a delegation once the minimum delegation stake has been reached
    // STAKING: the DAO has an active delegation
    // REVOKING: the DAO has scheduled a delegation revoke
    // REVOKED: the scheduled revoke has been executed
    enum daoState{ COLLECTING, STAKING, REVOKING, REVOKED }

    enum govStatusState{ NOTSTART, WINNING, LOSING }

    enum govTypeState{NONE, REVOKE, RESET  }


    // Current state that the DAO is in
    daoState public currentState;

    // Current state that the DAO is in
    govStatusState public currentGovStatusState;

    // Current state that the DAO is in
    govTypeState public currentGovTypeState;

    // Member stakes (doesnt include rewards, represents member shares)
    mapping(address => uint256) public memberStakes;

    // Number of vote for that address
    mapping(address => uint256) public memberVote;


    // Total Staking Pool (doesnt include rewards, represents total shares)
    uint256 public totalStake;

    // aye vote
    uint256 public ayeVote;

     // nay vote
    uint256 public nayVote;

    // total vote
    uint256 public totalVote;

    //current time
    uint256 public startTime;

    // The ParachainStaking wrapper at the known pre-compile address. This will be used to make
    // all calls to the underlying staking solution
    ParachainStaking public staking;

    // Minimum Delegation Amount
    uint256 public constant minDelegationStk = 5 ether;

    // Moonbeam Staking Precompile address
    address public constant stakingPrecompileAddress = 0x0000000000000000000000000000000000000800;

    // The collator that this DAO is currently nominating
    address public target;

    // Event for a member deposit
    event deposit(address indexed _from, uint _value);

    // Event for a member withdrawal
    event withdrawal(address indexed _from, address indexed _to, uint _value);

    // Initialize a new DelegationDao dedicated to delegating to the given collator target.
    constructor(address _target) {

        //Sets the collator that this DAO nominating
        target = _target;

        // Initializes Moonbeam's parachain staking precompile
        staking = ParachainStaking(stakingPrecompileAddress);

        //Initializes Roles
        // _setupRole(DEFAULT_ADMIN_ROLE, admin);
        // _setupRole(MEMBER, admin);

        //Initialize the DAO state
        currentState = daoState.COLLECTING;

    }

    // Grant a user the role of admin
    function grant_admin(address newAdmin)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
        onlyRole(MEMBER)
    {
        grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        grantRole(MEMBER, newAdmin);
    }

    // Grant a user membership
    function grant_member(address newMember)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        grantRole(MEMBER, newMember);
    }

    // Revoke a user membership
    function remove_member(address payable exMember)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        revokeRole(MEMBER, exMember);
    }

    // Increase member stake via a payable function and automatically stake the added amount if possible
    function add_stake() external payable onlyRole(MEMBER) {
        if (currentState == daoState.STAKING ) {
            // Sanity check
            if(!staking.is_delegator(address(this))){
                 revert("The DAO is in an inconsistent state.");
            }
            memberStakes[msg.sender] = memberStakes[msg.sender].add(msg.value);
            totalStake = totalStake.add(msg.value);
            emit deposit(msg.sender, msg.value);
            staking.delegator_bond_more(target, msg.value);
        }
        else if  (currentState == daoState.COLLECTING ){
            memberStakes[msg.sender] = memberStakes[msg.sender].add(msg.value);
            totalStake = totalStake.add(msg.value);
            emit deposit(msg.sender, msg.value);
            if(totalStake < minDelegationStk){
                return;
            } else {
                //initialiate the delegation and change the state
                staking.delegate(target, address(this).balance, staking.candidate_delegation_count(target), staking.delegator_delegation_count(address(this)));
                currentState = daoState.STAKING;
            }
        }
        else {
            revert("The DAO is not accepting new stakes in the current state.");
        }
    }

    // Function for a user to withdraw their stake
    function withdraw(address payable account) public onlyRole(MEMBER) {
        require(currentState != daoState.STAKING, "The DAO is not in the correct state to withdraw.");
        if (currentState == daoState.REVOKING) {
            bool result = execute_revoke();
            require(result, "Schedule revoke delay is not finished yet.");
        }
        if (currentState == daoState.REVOKED || currentState == daoState.COLLECTING) {
            //Sanity checks
            if(staking.is_delegator(address(this))){
                 revert("The DAO is in an inconsistent state.");
            }
            require(totalStake!=0, "Cannot divide by zero.");
            //Calculate the withdrawal amount including staking rewards
            uint amount = address(this)
                .balance
                .mul(memberStakes[msg.sender])
                .div(totalStake);
            require(check_free_balance() >= amount, "Not enough free balance for withdrawal.");
            Address.sendValue(account, amount);
            totalStake = totalStake.sub(memberStakes[msg.sender]);
            memberStakes[msg.sender] = 0;
            emit withdrawal(msg.sender, account, amount);
        }
    }

    // Schedule revoke, admin only
    // function schedule_revoke() public onlyRole(DEFAULT_ADMIN_ROLE){
    //     require(currentState == daoState.STAKING, "The DAO is not in the correct state to schedule a revoke.");
    //     staking.schedule_revoke_delegation(target);
    //     currentState = daoState.REVOKING;
    // }

    //Init governance, can switch between governance type
    function init_governance(govTypeState govTypeToSet) public payable onlyRole(MEMBER){
        //Hold at least 5 to vote
         require(memberStakes[msg.sender] < 5 , "Need to stake at least 5 to vote");
         require(msg.value < totalStake / 3, "Can't vote more than 1/3 of total staking amount");
        //
        if (currentGovStatusState == govStatusState.NOTSTART || block.timestamp > startTime + 1 days){
            //Initial vote counts
            ayeVote = 0;
            nayVote = 0;
            totalVote = 0;
            startTime = block.timestamp;
            //Initial vote type
            currentGovTypeState = govTypeToSet;
            //Initial vote status
            currentGovStatusState = govStatusState.WINNING;
            //Assign user voting amount
            require(msg.value <= memberStakes[msg.sender], "Not enough voting power");
            memberVote[msg.sender] = memberStakes[msg.sender].add(msg.value);
            ayeVote = ayeVote + msg.value;
            totalVote = totalVote + msg.value;

        }
        else{
            revert("Wait for current DAO governance to finish");
        }
    }

    //vote yes to governance
    function vote_yes() public payable onlyRole(MEMBER){
        require(memberStakes[msg.sender] < 5 , "Need to stake at least 5 to vote");
        require(msg.value < totalStake / 3, "Can't vote more than 1/3 of total staking amount");
        require(currentGovStatusState != govStatusState.NOTSTART, "Can't vote if no governance exists");
        require(msg.value <= memberStakes[msg.sender], "Not enough voting power");
        memberVote[msg.sender] = memberStakes[msg.sender].add(msg.value);
        totalVote = totalVote + msg.value;
        nayVote = nayVote + msg.value;
        process_vote();
    }

    //vote no to governance
    function vote_no() public payable onlyRole(MEMBER){
        require(memberStakes[msg.sender] < 5 , "Need to stake at least 5 to vote");
        require(msg.value < totalStake / 3, "Can't vote more than 1/3 of total staking amount");
        require(currentGovStatusState != govStatusState.NOTSTART, "Can't vote if no governance exists");
        require(msg.value <= memberStakes[msg.sender], "Not enough voting power");
        memberVote[msg.sender] = memberStakes[msg.sender].add(msg.value);
        totalVote = totalVote + msg.value;
        ayeVote = ayeVote + msg.value;
        process_vote();

    }

    // Schedule revoke by governance
    function schedule_revoke() public onlyRole(MEMBER){
        require(currentState == daoState.STAKING, "The DAO is not in the correct state to schedule a revoke.");
        staking.schedule_revoke_delegation(target);
        currentState = daoState.REVOKING;
    }

    // Process voting result
    function process_vote() public {
        if (nayVote > ayeVote){
            currentGovStatusState = govStatusState.LOSING;
        }
        else{
            currentGovStatusState = govStatusState.WINNING;
        }

        //If more than turnout rate > 50% or governance has been 24 hours, then time to see the result
        if (totalVote >= totalStake / 2 || block.timestamp > startTime + 1 days){
            if (currentGovStatusState == govStatusState.WINNING){
                if (currentGovTypeState == govTypeState.REVOKE){
                    schedule_revoke();
                }else{
                    reset_dao();
                }
            }
            else{
                return;
            }
            currentGovStatusState == govStatusState.NOTSTART;
            startTime = block.timestamp;
            currentGovTypeState = govTypeState.NONE;
        }
        else{
            return;
        }
    }

    // Try to execute the revoke, returns true if it succeeds, false if it doesn't
    function execute_revoke() internal onlyRole(MEMBER) returns(bool) {
        require(currentState == daoState.REVOKING, "The DAO is not in the correct state to execute a revoke.");
        staking.execute_delegation_request(address(this), target);
        if (staking.is_delegator(address(this))){
            return false;
        } else {
            currentState = daoState.REVOKED;
            return true;
        }
    }

    // Check how much free balance the DAO currently has. It should be the staking rewards if the DAO state is anything other than REVOKED or COLLECTING.
    function check_free_balance() public view onlyRole(MEMBER) returns(uint256) {
        return address(this).balance;
    }

    // Check current gov type
    function check_current_gov_type() public view onlyRole(MEMBER) returns(govTypeState) {
        return currentGovTypeState;
    }

    // Change the collator target, admin only
    function change_target(address newCollator) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(currentState == daoState.REVOKED || currentState == daoState.COLLECTING, "The DAO is not in the correct state to change staking target.");
        target = newCollator;
    }

    // // Reset the DAO state back to COLLECTING, admin only
    // function reset_dao() public onlyRole(DEFAULT_ADMIN_ROLE) {
    //     currentState = daoState.COLLECTING;
    // }

    // Reset Dao by governance
    function reset_dao() public onlyRole(MEMBER) {
        currentState = daoState.COLLECTING;
    }

}
