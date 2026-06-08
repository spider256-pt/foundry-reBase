//SPD-license-Identifier: MIT

pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IReBaseToken} from "./interfaces/IReBaseToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";

contract RebaseTokenPool is TokenPool {

    constructor (
        IERC20 _token,
        // uint8 _tokenDecimals,
        address[] memory _allowlist,
        address _rnmProxy,
        address _router
    ) TokenPool(_token, 18, _allowlist, _rnmProxy, _router){
        //Constructor body if additional logic
    }

    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockorBurnIn) public override returns(Pool.LockOrBurnOutV1 memory lockOrBurnOut) {
       _validateLockOrBurn(lockorBurnIn);

       //Decode the original sender's address 
       //Fetch the user's current Interest Rate from the ReBase Token contract
       uint256 userInterestRate = IReBaseToken(address(i_token)).getUserInterestRate(lockorBurnIn.originalSender);
      
       //Burn the specified amount of ReBase tokens from this pool contract
       // CCIP Transfer tokens to the pool before lockOrBurn is called 
       IReBaseToken(address(i_token)).burn(address(this), lockorBurnIn.amount);

       //Prepare Output data for CCIP
       lockOrBurnOut = Pool.LockOrBurnOutV1({
        destTokenAddress: getRemoteToken(lockorBurnIn.remoteChainSelector),
        destPoolData: abi.encode(userInterestRate) // Encode the user's interest rate to be sent to the destination chain
       });

    }

    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn) public override returns(Pool.ReleaseOrMintOutV1 memory releaseOrMintOut) {
        
        _validateReleaseOrMint(releaseOrMintIn);

        //Decode user Interest Rate 
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));

        //The receiver address is directly avaiable
        address receiver = releaseOrMintIn.receiver;

        //Mint tokens to the reciever, applying the propagated interest rate .abi
        IReBaseToken(address(i_token)).mint(
            receiver,
            releaseOrMintIn.amount,
            userInterestRate
        );

        return Pool.ReleaseOrMintOutV1({
            destinationAmount: releaseOrMintIn.amount
        });

    }

}