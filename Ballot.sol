pragma solidity  ^0.4.17;

library SafeMath {

    function mul(uint a, uint b) internal pure returns(uint) {
        uint c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
    }
    
    function sub(uint a, uint b) internal pure  returns(uint) {
        assert(b <= a);
        return a - b;
    }

    function add(uint a, uint b) internal  pure returns(uint) {
        uint c = a + b;
        assert(c >= a && c >= b);
        return c;
    }
}


contract ERC20 {
    uint public totalSupply;

    function balanceOf(address who) public view returns(uint);

    function allowance(address owner, address spender) public view returns(uint);

    function transfer(address to, uint value) public returns(bool ok);

    function transferFrom(address from, address to, uint value) public returns(bool ok);

    function approve(address spender, uint value) public returns(bool ok);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}


/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {

    address public owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function Ownable() public {
        owner = msg.sender;
    }
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
    function transferOwnership(address newOwner) onlyOwner public {
        require(newOwner != address(0));
        OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

contract TokenVesting is Ownable {
    using SafeMath for uint;

    struct TokenHolder {
        uint weiReceived;       // amount of ETH contributed
        uint tokensSent;        // amount of tokens  sent  
        bool refunded;          // true if user has been refunded       
        uint releasedAmount;    // amount released through vesting schedule
    }
    
    //Token public token;             // token contract containing tokens
    mapping(address => TokenHolder) public tokenHolders; //tokenHolder list
}

// Crowdsale Smart Contract
// This smart contract collects ETH and in return sends  tokens to the Backers
contract Crowdsale is TokenVesting {

    using SafeMath for uint;

    address public creatorWallet;       // Multisig contract that will receive the ETH
    uint public ethReceived;            // Number of ETH received in main sale
    uint public totalTokensSent;        // Number of tokens sent to ETH contributors
    uint public tokensSentDev;          // Tokens sent to dev team
    uint public startBlock;             // Crowdsale start block
    uint public endBlock;               // Crowdsale end block
    uint public maxCap;                 // Maximum number of token to sell
    uint public minCap;                 // Minimum number of ETH to raise
    uint public minContribution;        // Minimum amount to contribute in main sale
    uint public maxContribution;        // Max contribution which can be sent during ICO    
    uint public tokenPriceWei;          // Token price in We
    uint public campaignDurationDays;   // campaign duration in days 
    uint public firstPeriod;            // Length of first bonus period in days
    uint public secondPeriod;           // Length of second bonus period in days 
    uint public thirdPeriod;            // Lenght of third bonus period in days 
    uint public firstBonus;             // Amount of first bonus in %
    uint public secondBonus;            // Amount of second bonus in %
    uint public thirdBonus;             // Amount of third bonus in %
    uint public multiplier;             // Value representing number of decimal valus for token
    Step public currentStep;            // To allow for controlled steps of the campaign 
    Token public token;                 // token contract containing tokens
   
    address[] public holdersIndex;      // to be able to iterate through backers when distributing the tokens

    // @notice to set and determine steps of crowdsale
    enum Step {     
        
        Preparation,         // Crowdsale didn't start yet, to be initiated
        FundingCrowdsale,    // Crowdsale is active and collecting contributions
        Refunding,           // In case campaign failed during set this step to allow refunds
        Finished             // Crowdsale was completed, tokens distributed and unsold tokens were burned
    }

    // @notice to verify if action is not performed out of the campaign range
    modifier respectTimeFrame() {
        if ((block.number < startBlock) || (block.number > endBlock)) 
            revert();
        _;
    }

    // Events
    event LogReceivedETH(address indexed backer, uint amount, uint tokenAmount);
    event LogStarted(uint startBlockLog, uint endBlockLog);
    event LogFinalized(bool success);  
    event LogDevTokensAllocated(address indexed dev, uint amount);
    event LogTokensSent(address indexed user, uint amount);

    // Crowdsale  {constructor}
    // @notice fired when contract is crated. Initilizes all constnat variables.
    function Crowdsale(uint _decimalPoints,
                        address _creatorWallet,
                        uint _minContribution,
                        uint _maxContribution,                        
                        uint _maxCap, 
                        uint _minCap, 
                        uint _tokenPriceWei, 
                        uint _campaignDurationDays,
                        uint _firstPeriod, 
                        uint _secondPeriod, 
                        uint _thirdPeriod, 
                        uint _firstBonus, 
                        uint _secondBonus,
                        uint _thirdBonus) public payable {
        multiplier = 10**_decimalPoints;
        creatorWallet = _creatorWallet;
        minContribution = _minContribution;
        maxContribution = _maxContribution * (10**18);       
        maxCap = _maxCap * multiplier;       
        minCap = _minCap * multiplier;
        tokenPriceWei = _tokenPriceWei;
        campaignDurationDays = _campaignDurationDays;
        firstPeriod = _firstPeriod * 4 * 60 * 24;   //assumption that each block takes 15 seconds 
        secondPeriod = _secondPeriod * 4 * 60 * 24; //assumption that each block takes 15 seconds
        thirdPeriod = _thirdPeriod * 4 * 60 * 24;   //assumption that each block takes 15 seconds
        firstBonus = _firstBonus;
        secondBonus = _secondBonus;
        thirdBonus = _thirdBonus;               
        currentStep = Step.Preparation;
    }

    // @notice to populate website with status of the sale 
    function returnWebsiteData() external view returns(uint, 
        uint, uint, uint, uint, uint, uint, uint, uint, uint, Step) {
    
        return (startBlock, endBlock, numberOfBackers(), ethReceived, maxCap, minCap, 
                totalTokensSent, tokenPriceWei, minContribution, token.decimals(), currentStep);
    }
    
    // @notice this function will determine status of crowdsale
    function determineStatus() external view returns (uint) {
                      
        if (currentStep == Step.Preparation)           // ICO hasn't been started yet 
            return 1;  
        if (currentStep == Step.FundingCrowdsale)      // ICO in progress
            return 2;   
        if (currentStep == Step.Finished)              // ICO finished
            return 3;               
        if (currentStep == Step.Refunding)             // ICO failed    
            return 4;            
    
        return 0;         
    } 

    // {fallback function}
    // @notice It will call internal function which handels allocation of Ether and calculates tokens.
    function () public payable {    
             
        contribute(msg.sender);
    }

    // @notice to allow for contribution from interface
    function contributePublic() external payable {
        contribute(msg.sender);
    }

    // @notice It will be called by owner to start the sale    
    // @TODO it needs to be improved so block duration needs can be adjusted
    function initiateCrowdsale(Token _tokenAddress) external onlyOwner() {
        require(currentStep == Step.Preparation);
        token = _tokenAddress;
        startBlock = block.number;
        endBlock = startBlock + (4*60*24*campaignDurationDays); // assumption is that one block takes 15 sec. 
        currentStep = Step.FundingCrowdsale;
        LogStarted(startBlock, endBlock);
        //return true;
    }

    // @notice This function will finalize the sale.
    // It will only execute if predetermined sale time passed or all tokens are sold.
    function finalize() external onlyOwner() {

        require(currentStep == Step.FundingCrowdsale);
        require(block.number >= endBlock || totalTokensSent == maxCap);
        require(totalTokensSent >= minCap);
        currentStep = Step.Finished;
        
        // transfer remainng funds to the creator wallet
        LogFinalized(true);
        
        token.burn();
        token.unlock();    // release lock from transfering tokens. 
        creatorWallet.transfer(this.balance);
    }

    // @notice allocate tokens to dev/team/advisors
    // @param _dev {address} 
    // @param _amount {uint} amount of tokens
    function teamAllocation(Token _token, address _dev, uint _amount) external onlyOwner() returns (bool) {

        require(_dev != address(0));
        require(currentStep == Step.Preparation); 
        uint toSend = _amount * multiplier;
        require(totalTokensSent.add(toSend) <= maxCap);
        
        tokensSentDev = tokensSentDev.add(toSend);   
        totalTokensSent = totalTokensSent.add(toSend);    
        _token.transfer(_dev, toSend); 
        //LogDevTokensAllocated(_dev, toSend); // Register event
        return true;
    }

    // @notice transfer tokens which are not subject to vesting
    // @param _recipient {addres}
    // @param _amont {uint} amount to transfer
    function transferTokens(address _recipient, uint _amount) external onlyOwner() returns (bool) {
      
        require(_recipient != address(0));
        if (!token.transfer(_recipient, _amount))
            revert();
        LogTokensSent(_recipient, _amount);
        return true;
    }

    // @notice return number of contributors
    // @return  {uint} number of contributors
    function numberOfBackers() public view returns (uint) {
        return holdersIndex.length;
    }

    // @notice It will be called by fallback function whenever ether is sent to it
    // @param  _backer {address} address of beneficiary
    // @return res {bool} true if transaction was successful
    function contribute(address _backer) internal respectTimeFrame returns(bool res) {

        require(msg.value <= maxContribution);
        require(currentStep == Step.FundingCrowdsale);
        
        uint tokensToSend = calculateNoOfTokensToSend(); // calculate number of tokens
        uint tokensAvailable = maxCap - totalTokensSent;
        
        if(tokensAvailable < tokensToSend){
            uint tokensCost = tokensAvailable.mul(tokenPriceWei) / multiplier; // gives token cost in eth
            uint remainingETH = msg.value - tokensCost;
            
            tokensToSend = tokensAvailable;
            _backer.transfer(remainingETH);
        }
        
        // Ensure that max cap hasn't been reached
        require(totalTokensSent.add(tokensToSend) <= maxCap);
        
        TokenHolder storage backer = tokenHolders[_backer];

        if (backer.weiReceived == 0)
            holdersIndex.push(_backer);

        if (Step.FundingCrowdsale == currentStep) { // Update the total Ether received and tokens sent during public sale
            require(msg.value >= minContribution);  // stop when required minimum is not met    
            ethReceived = ethReceived.add(msg.value);
        } 
       
        backer.tokensSent = backer.tokensSent.add(tokensToSend);
        backer.weiReceived = backer.weiReceived.add(msg.value);       
        totalTokensSent = totalTokensSent.add(tokensToSend);
        token.transfer(_backer, tokensToSend);
        LogReceivedETH(_backer, msg.value, tokensToSend); // Register event
        return true;
    }

    // @notice This function will return number of tokens based on time intervals in the campaign
    function calculateNoOfTokensToSend() internal view returns (uint) {

        uint tokenAmount = msg.value.mul(multiplier) / tokenPriceWei;

        if (Step.FundingCrowdsale == currentStep) {
        
            if (block.number <= startBlock + firstPeriod) {  
                return  tokenAmount.add(tokenAmount.mul(firstBonus) / 100);
            }else if (block.number <= startBlock + secondPeriod) {
                return  tokenAmount.add(tokenAmount.mul(secondBonus) / 100); 
            }else if (block.number <= startBlock + thirdPeriod) { 
                return  tokenAmount.add(tokenAmount.mul(thirdBonus) / 100);        
            }else {              
                return  tokenAmount;
            }
        }
    }
}


// The  token
contract Token is ERC20, Ownable {

    using SafeMath for uint;
    // Public variables of the token
    string public name;
    string public symbol;
    uint public decimals; // How many decimals to show.
    string public version = "v0.1";
    uint public totalSupply;
    bool public locked;
    address public crowdSaleAddress;

    mapping(address => uint) public balances;
    mapping(address => mapping(address => uint)) public allowed;
    
    // Lock transfer during the ICO
    modifier onlyUnlocked() {
        if (msg.sender != crowdSaleAddress && locked && msg.sender != owner) 
            revert();
        _;
    }

    modifier onlyAuthorized() {
        if (msg.sender != crowdSaleAddress && msg.sender != owner) 
            revert();
        _;
    }

    // The Token constructor     
    function Token(uint _initialSupply,
            string _tokenName,
            uint _decimalUnits,
            string _tokenSymbol,
            string _version,
            address _crowdSaleAddress) public {      
        locked = true;  // Lock the transfer of tokens during the crowdsale
        totalSupply = _initialSupply * (10**_decimalUnits);     
                                        
        name = _tokenName;          // Set the name for display purposes
        symbol = _tokenSymbol;      // Set the symbol for display purposes
        decimals = _decimalUnits;   // Amount of decimals for display purposes
        version = _version;
        crowdSaleAddress = _crowdSaleAddress;              
        balances[crowdSaleAddress] = totalSupply;
        Transfer(0, crowdSaleAddress, totalSupply);
    }

    function unlock() public onlyAuthorized {
        locked = false;
    }

    function lock() public onlyAuthorized {
        locked = true;
    }

    function burn() public onlyAuthorized returns(bool) {
        Transfer(crowdSaleAddress, 0x0, balances[crowdSaleAddress]);
        //totalSupply = totalSupply.sub(balances[crowdSaleAddress]);
        balances[crowdSaleAddress] = 0;
        
        return true;
    }

   
    // @notice transfer tokens to given address
    // @param _to {address} address or recipient
    // @param _value {uint} amount to transfer
    // @return  {bool} true if successful
    function transfer(address _to, uint _value) public onlyUnlocked returns(bool) {

        require(_to != address(0));
        require(balances[msg.sender] >= _value);
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        Transfer(msg.sender, _to, _value);
        return true;
    }

    // @notice transfer tokens from given address to another address
    // @param _from {address} from whom tokens are transferred
    // @param _to {address} to whom tokens are transferred
    // @param _value {uint} amount of tokens to transfer
    // @return  {bool} true if successful
    function transferFrom(address _from, address _to, uint256 _value) public onlyUnlocked returns(bool success) {

        require(_to != address(0));
        require(balances[_from] >= _value); // Check if the sender has enough
        require(_value <= allowed[_from][msg.sender]); // Check if allowed is greater or equal
        balances[_from] = balances[_from].sub(_value); // Subtract from the sender
        balances[_to] = balances[_to].add(_value); // Add the same to the recipient
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value); // adjust allowed
        Transfer(_from, _to, _value);
        return true;
    }

    // @notice to query balance of account
    // @return _owner {address} address of user to query balance
    function balanceOf(address _owner) public view returns(uint balance) {
        return balances[_owner];
    }

    /**
    * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
    *
    * Beware that changing an allowance with this method brings the risk that someone may use both the old
    * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
    * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
    * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    * @param _spender The address which will spend the funds.
    * @param _value The amount of tokens to be spent.
    */
    function approve(address _spender, uint _value) public returns(bool) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    // @notice to query of allowance of one user to the other
    // @param _owner {address} of the owner of the account
    // @param _spender {address} of the spender of the account
    // @return remaining {uint} amount of remaining allowance
    function allowance(address _owner, address _spender) public view returns(uint remaining) {
        return allowed[_owner][_spender];
    }
}
