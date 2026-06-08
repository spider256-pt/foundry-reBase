//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24; 

import {Script, console} from "forge-std/Script.sol";
import {Vault} from "../src/Vault.sol";
import {IReBaseToken} from "../src/interfaces/IReBaseToken.sol";
import {ReBaseToken} from "../src/ReBase.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";






contract VaultDeployer is Script {

    IReBaseToken i_reBaseToken;

    function run(address _rebasetoken) external returns(Vault vault) {
        vm.startBroadcast();
        vault = new Vault(IReBaseToken(_rebasetoken));
        IReBaseToken(_rebasetoken).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();
        return vault;
    }
}

contract TokenAndTokenPoolDeployer is Script {
  
   function run() public returns(ReBaseToken token, RebaseTokenPool pool) {

        CCIPLocalSimulatorFork ccipLocalSimulator = new CCIPLocalSimulatorFork();

        Register.NetworkDetails memory networkDetails = ccipLocalSimulator.getNetworkDetails(block.chainid);

        

        vm.startBroadcast();
        token = new ReBaseToken();
        pool = new RebaseTokenPool(
            
            IERC20(address(token)),
            new address[](0),
            networkDetails.rmnProxyAddress,
            networkDetails.routerAddress
        );

        token.grantMintAndBurnRole(address(pool));
        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(address(token), address(pool));
    
        vm.stopBroadcast();
        return (token, pool);
   }
}   