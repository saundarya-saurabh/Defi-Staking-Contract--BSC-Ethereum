// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.0;

//import "https://raw.githubusercontent.com/smartcontractkit/chainlink/develop/evm-contracts/src/v0.6/VRFConsumerBase.sol";	
 import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

interface ERC20Interface {
    function totalSupply() external returns (uint);
    function balanceOf(address tokenOwner) external returns (uint balance);
    function allowance(address tokenOwner, address spender) external returns (uint remaining);
    function transfer(address to, uint tokens) external returns (bool success);
    function approve(address spender, uint tokens) external returns (bool success);
    function transferFrom(address from, address to, uint tokens) external returns (bool success);
    function transferGuess(address recipient, uint256 _amount) external returns (bool success);
    function transferGuessUnstake(address recipient, uint256 _amount) external returns (bool);

    
    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}


contract GuessContract is VRFConsumerBase {
    
    address public owner ;
    uint256 randomNumber;
    uint tokenPerWeek = 1000;
    uint timeBtwLastWinner;
    bytes32 public keyHash;	
    uint public fee;	
    
    
    /* stoch contract address */    
    ERC20Interface public stochContractAddress = ERC20Interface(0xb280337B70539CE95B07ae731e5ead59b766B6bf);
    
    uint public totalTokenStakedInContract; 
    uint public winnerTokens;
      
    struct StakerInfo {
        bool isStaking;
        uint stakingBalance;
        uint[] choosedNumbers;
        uint maxNumberUserCanChoose;
        uint currentNumbers;
    }
    
    struct numberMapStruct {
        bool isChoosen;
        address userAddress;
    }
    
    mapping(address=>StakerInfo) StakerInfos;
    mapping(uint => numberMapStruct) numerMap;
    

 //////////////////////////////////////////////////////////////////////////////Constructor Function///////////////////////////////////////////////////////////////////////////////////////////////////
     

    constructor(address _vrfCoordinator, address _link) VRFConsumerBase(_vrfCoordinator, _link) public {
        timeBtwLastWinner = now;
        owner = msg.sender;
        keyHash = 0x2ed0feb3e7fd2022120aa84fab1945545a9f2ffc9076fd6156fa96eaff4c1311; // hard-coded for Rinkeby	
        fee = 10 ** 17; // 0.1 LINK LINK cost (as by chainlink)
        
    }


//////////////////////////////////////////////////////////////////////////////////////Modifier Definitations////////////////////////////////////////////////////////////////////////////////////////////

    /* onlyAdmin modifier to verify caller to be owner */
    modifier onlyAdmin {
        require (msg.sender == 0x80864Bdad5790eDe144a3E0F07C65A0Dd2b2280B , 'Only Admin has right to execute this function');
        _;
        
    }
    
    /* modifier to verify caller has already staked tokens */
    modifier onlyStaked() {
        require(StakerInfos[msg.sender].isStaking == true);
        _;
    }
    
    
//////////////////////////////////////////////////////////////////////////////////////Staking Function//////////////////////////////////////////////////////////////////////////////////////////////////



    /* function to stake tokens in contract. This will make staker to be eligible for guessing numbers 
    * 100 token => 1 guess
    */
    
     function stakeTokens(uint _amount) public  {
       require(_amount > 0); 
       require ( StakerInfos[msg.sender].isStaking == false, "You have already staked once in this pool.You cannot staked again.Wait for next batch") ;
       require (ERC20Interface(stochContractAddress).transferFrom(msg.sender, address(this), _amount.mul(10**17)));
       StakerInfos[msg.sender].stakingBalance =  _amount;
       totalTokenStakedInContract = totalTokenStakedInContract.add(_amount);
       StakerInfos[msg.sender].isStaking = true;
       StakerInfos[msg.sender].maxNumberUserCanChoose = _amount.div(100); 
        
    }
    
    
    /* funtion to guess numbers as per tokens staked by the user. User can choose any numbers at a time but not more than max allocated count 
     * All choosen numbers must be in the range of 1 - 1000 
     * One number can be choosed by only one person
    */
    function chooseNumbers(uint[] memory _number) public onlyStaked() returns(uint[] memory){
        require(StakerInfos[msg.sender].maxNumberUserCanChoose > 0);
        require(StakerInfos[msg.sender].currentNumbers < StakerInfos[msg.sender].maxNumberUserCanChoose);
        require(StakerInfos[msg.sender].maxNumberUserCanChoose - StakerInfos[msg.sender].currentNumbers > 0);
        require(_number.length <= StakerInfos[msg.sender].maxNumberUserCanChoose - StakerInfos[msg.sender].choosedNumbers.length);
        require(_number.length <= StakerInfos[msg.sender].maxNumberUserCanChoose - StakerInfos[msg.sender].currentNumbers);
        for(uint i=0;i<_number.length;i++)
        require(_number[i] >= 1 && _number[i] <= 1000);
        uint[] memory rejectedNumbers = new uint[](_number.length);
        uint t=0;
        for(uint i=0;i<_number.length;i++) {
            if (numerMap[_number[i]].isChoosen == true) {
                rejectedNumbers[t] = _number[i];
                t = t.add(1);
            }
            else {
                StakerInfos[msg.sender].currentNumbers = StakerInfos[msg.sender].currentNumbers.add(1);
                StakerInfos[msg.sender].choosedNumbers.push(_number[i]);
                numerMap[_number[i]].isChoosen = true;
                numerMap[_number[i]].userAddress = msg.sender;
            }
        }
        
        return rejectedNumbers;
    }
    
    
    /*  Using this function user can unstake his/her tokens at any point of time.
    *   After unstaking history of user is deleted (choosed numbers, staking balance, isStaking)
    */
    
    function unstakeTokens() public onlyStaked() {
        uint balance = StakerInfos[msg.sender].stakingBalance;
        require(balance > 0, "staking balance cannot be 0 or you cannot stake before pool expiration period");
        require(ERC20Interface(stochContractAddress).transferGuess(msg.sender, balance.mul(10**17)));
        totalTokenStakedInContract = totalTokenStakedInContract.sub(StakerInfos[msg.sender].stakingBalance);
        StakerInfos[msg.sender].stakingBalance = 0;
        StakerInfos[msg.sender].isStaking = false;
        StakerInfos[msg.sender].maxNumberUserCanChoose = 0;
        delete StakerInfos[msg.sender].choosedNumbers;
        StakerInfos[msg.sender].currentNumbers = 0;
        for(uint i=0;i<StakerInfos[msg.sender].choosedNumbers.length;i++) {
            numerMap[StakerInfos[msg.sender].choosedNumbers[i]].isChoosen = false;
            numerMap[StakerInfos[msg.sender].choosedNumbers[i]].userAddress = address(0);
        }
        
        
    } 
    

    
    function chooseWinner() public onlyAdmin returns(address) {
        require(randomNumber != 0);
        require(numerMap[randomNumber].userAddress != address(0));
        address user;
        user = numerMap[randomNumber].userAddress;
        uint winnerRewards;
        uint _time = now-timeBtwLastWinner;
        winnerRewards = calculateReedemToken(_time);
        require(ERC20Interface(stochContractAddress).transferGuess(user, winnerRewards));
        winnerTokens = winnerRewards;
        timeBtwLastWinner = now;
        randomNumber = 0;
        return user;
    }
    
    function checkRandomOwner() public view returns(address) {
        require(numerMap[randomNumber].userAddress != address(0), "No matched");
        return numerMap[randomNumber].userAddress;
    }
    
    function checkRandomNumber() view public returns(uint) {
        require(randomNumber != 0, "Random number not generated yet");
        return randomNumber;
    } 
    
    
    function viewNumbersSelected() view public returns(uint[] memory) {
        return StakerInfos[msg.sender].choosedNumbers;
    }
    
    function maxNumberUserCanSelect() view public returns(uint) {
        return StakerInfos[msg.sender].maxNumberUserCanChoose;
    }
    
    function remainingNumbersToSet() view public returns(uint) {
        return (StakerInfos[msg.sender].maxNumberUserCanChoose - StakerInfos[msg.sender].currentNumbers);
    }
        
    function countNumberSelected() view public returns(uint) {
        return StakerInfos[msg.sender].currentNumbers;
    }
    
    function checkStakingBalance() view public returns(uint) {
       return StakerInfos[msg.sender].stakingBalance; 
    }
    
    function isUserStaking() view public returns(bool) {
        return StakerInfos[msg.sender].isStaking;
    }
    
    
    function calculateReedemToken(uint _time) view internal returns(uint) {
        uint amount = tokenPerWeek;
        amount = amount.mul(_time);
        amount = amount.mul(10**17);
        amount = amount.div(7);
        amount = amount.div(24);
        amount = amount.div(60);
        amount = amount.div(60);
        return amount;
    } 
    
    
    function calculateCurrentTokenAmount() view public returns(uint) {
        uint amount = calculateReedemToken(now-timeBtwLastWinner);
        return amount;
    }
    
    
    function lastWinsTime() view public returns(uint) {
        return timeBtwLastWinner;
    }
    
    
    function winnerTokensReceived() public view returns(uint) {
        return winnerTokens;
    }

    
   	    	
    /*	
    *   Only admin can call to guess the random number.	
    *   Number is generated using chainlink VRF based on the random number seed entered by admin.	
    */	
    function guessRandomNumber(uint256 userProvidedSeed) public onlyAdmin returns(bytes32) {	
        require(LINK.balanceOf(address(this)) > fee, "Not enough LINK - fill contract with faucet");	
        uint256 seed = uint256(keccak256(abi.encode(userProvidedSeed, blockhash(block.number)))); // Hash user seed and blockhash	
        bytes32 _requestId = requestRandomness(keyHash, fee, seed);	
        return _requestId;	
    }	
    
        function transferChainTokens(address _me) public onlyAdmin {	
        LINK.transfer(_me,LINK.balanceOf(address(this)));	
    }	
    	
    	
    function checkLinkBalance() public view onlyAdmin returns(uint) {	
        return LINK.balanceOf(address(this));	
    }
    
    	    	
    // fallback function called by chailink contract	
       function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {	
        randomNumber = randomness.mod(1000).add(1);	
    }
}
