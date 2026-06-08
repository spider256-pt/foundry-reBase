//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IReBaseToken} from "./interfaces/IReBaseToken.sol";

contract Vault {


    //Core Requirements
    // 1. Store the address of the ReBase token contract (passed in the Constructor).
    // 2. Implement deposit function that 
    // - acceopts eth from the user
    // - Mints RebaseToken to the user, equivalent to the amount of eth send (1:1 peg initially)
    // 3. Implement ReedemFunction:
    // - Burns the user RebaseToken 
    // - Sends the corresponding amount od Eth back to the user
    // 4. Implement a mechanism to add ETH rewards to the vault. 

    IReBaseToken private immutable i_reBaseToken;
    
    event Deposit(address indexed user, uint256 amount);
    event Reedem(address indexed user, uint256 amount);

    error Vault__ReedemFailed();
    error Vault__DepositIsZero();

    constructor(IReBaseToken _rebaseToken){
        i_reBaseToken = _rebaseToken;
    }


    /**
     * @notice Deposits ETH into the vault and mints ReBase tokens.
     * @dev The amount of ETH sent with the transaction (msg.value) determines the amount of tokens minted.
     * Assume (1:1) peg initially fo ETH to ReBase token for simplicity.
     */
    function deposit() external payable {

        i_reBaseToken.mint(msg.sender, msg.value, i_reBaseToken.getGlobalInterestRate());
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allow user to burn their RebaseTokens and receive a corresponding amount of ETH back.
     * @param _amount The amount of ReBase tokens the user wants to redeem for ETH
     * @dev Follows CEI pattern. Uses low-level .call for ETG transfer.
    */
    function redeem(uint256 _amount) external {

        uint256 amountToRedeem = _amount;

        if(_amount == type(uint256).max){
            amountToRedeem = i_reBaseToken.balanceOf(msg.sender);
        }
        //1. Effect (State change occurs first)
        //Burn the specified amount of ReBase tokens from the caller(msg.sender)
        //The rebase token burn function should be handle checks for sufficient balance.
        i_reBaseToken.burn(msg.sender, amountToRedeem);

        //2. Interaction (External call/ ETH transfer last)
        //Send the equivalent amount of ETH back to the user(msg.sender)
        (bool success, ) = payable(msg.sender).call{value: amountToRedeem}("");

        //Checks if the transfer succeeeded
        if(!success){
            revert Vault__ReedemFailed();
        }

        emit Reedem(msg.sender, amountToRedeem);

    }
    /**
     * @notice Gets the Address of the ReBase token contract associated with this vault.
     * @return address of the ReBase token contract.
     */
    function getRebaseTokenAddress() external view returns(address){
        return address(i_reBaseToken);
    }

    /**
     * @notice Fallback function to accept ETH rewards sent directly to the vault.
     * @dev Any Eth sent to this contract's address without data will be accepted.
     */
    receive() external payable {
        // Accept ETH rewards sent directly to the vault
    }

}