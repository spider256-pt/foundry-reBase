//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Vault} from "../../src/Vault.sol";
import {ReBaseToken} from "../../src/ReBase.sol";
import {IReBaseToken} from "../../src/interfaces/IReBaseToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RebaseTokenTest is Test {

    ReBaseToken public reBaseToken;
    Vault public vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");

    function addRewardsToVault(uint256 amount) public {
        payable(address(vault)).call{value: amount}("");
    }

    function setUp() public {

        vm.startPrank(owner);
        vm.deal(owner, 10 ether);
        //Deploy RebaseToken 
        reBaseToken = new ReBaseToken();
        //Deploy Vault
        vault = new Vault(IReBaseToken(address(reBaseToken)));
        //Grant MINT_AND_BURN_ROLE to the vault contract in the RebaseToken contract
        reBaseToken.grantMintAndBurnRole(address(vault));

        (bool success, ) = payable(address(vault)).call{value: 1 ether}("");
        require(success, "Failed to send ETH to the vault");
        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        // Bound minimum balance is set as 1e5 to avoid underflow.
        //Bound is used to set the maximum and minimum values for the amount variable.
        amount = bound(amount, 1e5, type(uint96).max);

        //User deposits 'amount' ETH
        vm.startPrank(user);
        vm.deal(user, amount);
        
        // Deposits the specified amount of ETH into the vault.
        vault.deposit{value: amount}();

        // Check the user's ReBase token balance after deposit
        uint256 userBalnce = reBaseToken.balanceOf(user);

        //Warp first time forward and check balance again to see the balance growth.abi
        uint256 timeDelta = 1 days;
        vm.warp(block.timestamp + timeDelta);
        uint256 userBalanceAfterFirstTimeWarp = reBaseToken.balanceOf(user);
        uint256 interestFirstPeriod = userBalanceAfterFirstTimeWarp - userBalnce;

        //Warp second time forward and check balance again to see the balance growth.
        vm.warp(block.timestamp + timeDelta);
        uint256 userBalanceAfterSecondTimeWarp = reBaseToken.balanceOf(user);
        uint256 interestSecondPeriod = userBalanceAfterSecondTimeWarp - userBalanceAfterFirstTimeWarp;

        //Assert that the interest earned in the second period is less than the interest earned in the first period, confirming that the interest rate is decreasing.
        assertApproxEqAbs(interestFirstPeriod, interestSecondPeriod, 1e5, "Interest earned in the second period should be approximately equal to the interest earned in the first period due to the decreasing interest rate");
        vm.stopPrank();
        //assertApproxEqAbs(value1, value2, delta) is used to check if values are approximately equal within a certain absolute tolerance (delta).

    }
    
    function testRedeemStraightAway(uint256 amount) public {
        //Arrange
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        //Act 
        vault.deposit{value: amount}();
        uint256 userBalance  = reBaseToken.balanceOf(user);
        console.log("User balance after deposit: ", userBalance);

        //Redeem 
        vault.redeem(type(uint256).max);
        uint256 userbalanceAfterReedem = reBaseToken.balanceOf(user);
        console.log("User balance after redeem: ", userbalanceAfterReedem);

        //assert
        assertGt(userBalance, 0, "User balance should be greater than 0 after deposit");
        assertEq(userbalanceAfterReedem, 0, "User balance should be 0 after redeeming all tokens");
        vm.stopPrank();
    }

    function testRedeemAfterTimeWarp(uint256 amount, uint256 time) public {
        //Arrange 
        time = bound(time, 1000, type(uint96).max);

        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);

        //Act 
        vault.deposit{value: amount}();
        vm.warp(time);
        uint256 userBalance  = reBaseToken.balanceOf(user);
        vm.stopPrank();

        // Owner funds the vault with additional ETH to ensure there are sufficient funds for redemption, especially after interest accrual.
        vm.deal(owner, userBalance-amount);
        vm.prank(owner);
        addRewardsToVault(userBalance-amount);
        
        vm.stopPrank();
        //Redeem
        vm.startPrank(user);
        vault.redeem(userBalance);

        uint256 userbalanceAfterReedem = reBaseToken.balanceOf(user);
        //Assert 
        assertGt(userBalance, 0, "User balance should be greater than 0 after deposit");
        assertEq(userbalanceAfterReedem, 0, "User balance should be 0 after redeeming all tokens");
        assertGt(address(user).balance, amount, "User should receive more ETH than they deposited due to interest accrual");
        vm.stopPrank();

    }


    function testTransfer(uint256 amount, uint256 amountToSend) public {
        //Arrange
        amount = bound(amount, 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        console.log("User balance after deposit", reBaseToken.balanceOf(user));
        uint256 userInterestRate = reBaseToken.getUserInterestRate(user);
        vm.stopPrank();
        //Act 
        //Owner changes the Global interest rate to 4e10;
        vm.prank(owner);
        reBaseToken.setInterestRate(4e10);
        vm.stopPrank();
     

        vm.startPrank(user);
        console.log("user2 balance before transfer: ", reBaseToken.balanceOf(user2));
        reBaseToken.transfer(user2, amountToSend);
        console.log("User2 balance after transfer: ", reBaseToken.balanceOf(user2));
        console.log("User balance after transfer: ", reBaseToken.balanceOf(user));

        uint256 user2IniterestRate = reBaseToken.getUserInterestRate(user2);
        console.log("User2 interest rate after receiving tokens: ", user2IniterestRate);
        vm.stopPrank();
        //Assert 
        assertEq(reBaseToken.balanceOf(user), amount - amountToSend, "User balance should decrease by the amount sent");
        assertEq(reBaseToken.balanceOf(user2), amountToSend, "User2 balance should increase by the amount received");
        assertEq(userInterestRate, user2IniterestRate, "User2 should inherit the same interest rate as User after receiving tokens");
        assertEq(user2IniterestRate, 5e10, "User2 interest rate should be equal to the global interest rate at the time of transfer");
        
    }

    function testCheckPrincipleBalanceAfterDeposit(uint256 amount) public {
        //Arrange
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        //Act 
        vault.deposit{value: amount}();
        
        uint256 userBalance  = reBaseToken.balanceOf(user);
        console.log("User balance after deposit: ", userBalance);

        uint256 principleBalanceOftheUser = reBaseToken.principleBalnceOf(user);
        console.log("Principle balance of the user: ", principleBalanceOftheUser);
        //Assert
        assertGt(userBalance, 0, "User balance should be greater than 0 after deposit");
        assertEq(principleBalanceOftheUser, userBalance, "Principle balance should be equal to the initial deposit amount, excluding interest");
        vm.stopPrank();

    }

    function testCheckPrincipleBalanceAfterTimeWarp(uint256 amount, uint256 time) public {
        
        //Arrange
        amount = bound(amount, 1e5, type(uint96).max);
        time = bound(time, 1000, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        //Act 
        vault.deposit{value: amount}();
        
        uint256 userBalance  = reBaseToken.balanceOf(user);
        console.log("User balance after deposit: ", userBalance);
        vm.warp(time);
        uint256 updatedBalance = reBaseToken.balanceOf(user);
        console.log("User balance after time warp and before redeem: ", updatedBalance);

        uint256 principleBalanceOftheUser = reBaseToken.principleBalnceOf(user);
        console.log("Principle balance of the user: ", principleBalanceOftheUser);
        //Assert
        assertGt(userBalance, 0, "User balance should be greater than 0 after deposit");
        assertGt(updatedBalance, userBalance, "User balance should increase after time warp due to interest accrual");
        assertEq(principleBalanceOftheUser, userBalance, "Principle balance should be equal to the initial deposit amount, excluding interest");
        vm.stopPrank();

    }

    function testUserCannotSetInterestRate(uint256 amount) public {
        //Arrange
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        // uint256 userBalance = reBaseToken.balanceOf(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        //Act
        reBaseToken.setInterestRate(4e10);
        //Assert
        vm.stopPrank();
    }

    function testNonGrantedUSerCannotMintOrBurn(uint256 amount) public {
        
        amount = bound(amount, 1e5, type(uint96).max);
        uint256 globalInterestRate = reBaseToken.getGlobalInterestRate();
        
        vm.deal(user, amount);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        //Act
        vm.prank(user);
        reBaseToken.mint(user, 100, globalInterestRate);

        
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        vm.prank(user);
        reBaseToken.burn(user, 100);
    }

    

}