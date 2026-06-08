//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";



    /**
    * @title ReBase Token
    * @author Pratik Das
    * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
    * @notice The interest rate in the smart contract can only decrease.
    * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit.
    */
contract ReBaseToken is ERC20, Ownable, AccessControl{



    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = 5e10;
    mapping (address => uint256) private s_userInterestRate; //map to store a specific interest "locked in" for each user.
    mapping (address => uint256) private s_userLastUpdatedTimestamp; // map to store the timestamp of the last update for each user, used to calculate accrued interest.

    bytes32 public constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");


    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);
    event InterestRateSet(uint256 newInterestRate);

 

    constructor() ERC20("ReBase", "RBT") Ownable(msg.sender){
        // Initialization code if needed
    }


    function grantMintAndBurnRole(address _account) external onlyOwner{
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
    * @notice Set the global interest rate for the contract.
    * @param _newInterestRate The new interest rate to set(scaled by PRECISION_FACTOR).
    * @dev The new interest rate must be less than or equal to the current interest rate
    */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner{
        if (_newInterestRate > s_interestRate){
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
    * @notice Get the interest rate for a specific user.
    * @param _user The address of the user.
    * @return The interest rate for the user.
    */
    function getUserInterestRate(address _user) external view returns(uint256){
        return s_userInterestRate[_user];
    }

    /**
    * @notice Mints Tokens to a user, typically upon deposit.
    * @param _to Address to mint tokens to
    * @param _amount Amount of tokens to mint (scaled by PRECISION_FACTOR)
    */
    function mint(address _to, uint256 _amount, uint256 s_interestRate) external onlyRole(MINT_AND_BURN_ROLE){
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;   
        _mint(_to, _amount);
    }

    /**
    * @notice Burn the user tokens, e.g., when they withdraw from a vault or for cross-chain transfers.
    * Handles burning the entire balance if _amount is type(uint256).max.
    * @param _from The user address from which to burn tokens.
    * @param _amount The amount of tokens to burn. Use type(uint256).max to burn all tokens.
    */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {

       uint256 currentBalance = balanceOf(_from);

        if(_amount == type(uint256).max){
            _amount = currentBalance;
        }
        // Ensure _amount does not exceed actual balance after potential interest accrual
        // This check is important especially if _amount wasn't type(uint256).max
        // _mintAccruedInterest will update the super.balanceOf(_from)
        // So, after _mintAccruedInterest, super.balanceOf(_from) should be currentTotalBalance.
        // The ERC20 _burn function will typically revert if _amount > super.balanceOf(_from)
        _mintAccruedInterest(_from);

        // At this point, super.balanceOf(_from) reflects the balance including all interest up to now.
        // If _amount was type(uint256).max, then _amount == super.balanceOf(_from)
        // If _amount was specific, super.balanceOf(_from) must be >= _amount for _burn to succeed.
        _burn(_from, _amount);

    }

    /** 
    * @dev Internal function to calculate and mint accrued interest for a user.
    * @dev Updates the user's last updated timestamp
    * @param _user The address of the user to mint interest for.
    */
    function _mintAccruedInterest(address _user) internal {

       uint256 previousPrincipalBalance = super.balanceOf(_user);
       uint256 currentBalance = balanceOf(_user);
       uint256 balanceIncrease = currentBalance - previousPrincipalBalance;

        s_userLastUpdatedTimestamp[_user] = block.timestamp;

        if (balanceIncrease > 0){
             _mint(_user, balanceIncrease);
        }
    }

    /**
    * @notice Override the balanceOf function to return the dynamic balance including accrued interest.  
    * @param _user The address of the user to query the balance of.
    * @return The dynamic balance of the user including accrued interest.
    */
    function balanceOf(address _user) public view override returns (uint256) {
        uint256 principalBalance = super.balanceOf(_user);

        uint256 growthFactor = _calculateUserAccumulatedInterestSinceLastUpdate(_user);

        return (principalBalance * growthFactor) / PRECISION_FACTOR;
    }

    /** 
    * @dev Calculates the growth factor due to accumulated interest for a user since their last update.
    * @param _user The address of the user.
    * @return linearInteresetFactor The growth factor, scaled by PRECISION_FACTOR
    */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns(uint256 linearInteresetFactor){
        //1. Calculate the time elapsed since the user's balance was last effectively updated
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        
        //if no time passed, or if the user has no locked rate(e.g. never interacted),
        //the growth factor is simply 1 (scaled by PRECISION_FACTOR)
        if(timeElapsed == 0 || s_userInterestRate[_user] == 0){
            return PRECISION_FACTOR; // No time has passed, so no interest has accrued.
        }

        //2. Calculate the total fractional interest accrued: UserInteresetRate * TimeElapsed
        //s_interestRate[_user] is the rate per second.
        //This product is already scaled appropriately if s_userInterestRate is stored scaled.
        uint256 fractionalInterest = s_userInterestRate[_user] * timeElapsed;


        //3. The growth factor is then 1 + fractionalInterest.
        //Since '1' is represented as PRECISION_FACTOR, and fractionalInterest is already scaled, we add them
        linearInteresetFactor = PRECISION_FACTOR + fractionalInterest;
        return linearInteresetFactor;
    }



    /**
    * @notice Transfers token from sender to recipient
    * Accrued interest for both sender and recipient is minted before the transfer.
    * @param _recipient The address of the recipient.
    * @param _amount The amount of tokens to transfer.
    * @return A boolean value indicating whether the operation succeeded.
    */
    function transfer(address _recipient, uint256 _amount) public override returns(bool){
        //Mints accrued interest for both sender and recipient.abi
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);

        // Handle request to transfer maximum balance
        if(_amount == type(uint256).max){
            _amount = balanceOf(msg.sender);
        }

        // 3. Set recipient's interest rate if they are new (balance is checked *before* super.transfer)
        // We use balanceOf here to check the effective balance including any just-minted interest.
        // If _mintAccruedInterest made their balance non-zero, but they had 0 principle, this still means they are "new" for rate setting.
        // A more robust check for "newness" for rate setting might be super.balanceOf(_recipient) == 0 before any interest minting for the recipient.
        // However, the current logic is: if their *effective* balance is 0 before the main transfer part, they get the sender's rate.
        if (balanceOf(_recipient) == 0 && _amount > 0){
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }

        return super.transfer(_recipient, _amount);

    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns(bool){
        //Same coditions as the Transfer function, but for the sender and recipient in transferFrom.
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);

        if(_amount == type(uint256).max){
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0 && _amount > 0){
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
    * @notice Get the principal balance of a user, excluding accrued interest.
    * @param _user The address of the user to query the principal balance of.
    * @return The principal balance of the user.
    */
   function principleBalnceOf(address _user) external view returns(uint256){
        return super.balanceOf(_user);
    }

    /**
    * @notice Get current global interest rate.
    * @return The current global interest rate, scaled by PRECISION_FACTOR.
    */
   function getGlobalInterestRate() external view returns(uint256){
        return s_interestRate;
    }
    
}