// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {ReBaseToken} from "../../src/ReBase.sol";

import {RebaseTokenPool} from "../../src/RebaseTokenPool.sol";

import {Vault} from "../../src/Vault.sol";

import {IReBaseToken} from "../../src/interfaces/IReBaseToken.sol";

import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";

import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";

// Import the Chainlink Local Simulator

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

import {Client} from "@chainlink-local/lib/chainlink-ccip/chains/evm/contracts/libraries/Client.sol";

import {IRouterClient} from "@chainlink-local/lib/chainlink-ccip/chains/evm/contracts/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    // Structural optimization container to eliminate Yul stack-allocation issues

    struct BridgeContext {
        uint256 localFork;
        uint256 remoteFork;
        Register.NetworkDetails localNetworkDetails;
        Register.NetworkDetails remoteNetworkDetails;
        ReBaseToken localToken;
        ReBaseToken remoteToken;
        uint256 localBalanceBefore;
        uint256 fee;
    }

    uint256 public SEND_VALUE = 1e5;
    address owner = makeAddr("owner");
    address user = makeAddr("user");

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    
    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;
    ReBaseToken sepoliaToken;
    ReBaseToken arbSepoliaToken;

    TokenAdminRegistry tokenAdminRegistrySepolia;
    TokenAdminRegistry tokenAdminRegistryArbitrum;

    RegistryModuleOwnerCustom registryModuleOwnerCustomSepolia;
    RegistryModuleOwnerCustom registryModuleOwnerArbitrum;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    Vault vault;

    function setUp() public {
        sepoliaFork = vm.createFork("sepolia");
        arbSepoliaFork = vm.createFork("arb-sepolia");
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        vm.makePersistent(address(ccipLocalSimulatorFork));
        // 1. Deploy Phase: Source Chain (Sepolia)
        vm.selectFork(sepoliaFork);

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );

        vm.startPrank(owner);

        sepoliaToken = new ReBaseToken();

        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        vault = new Vault(IReBaseToken(address(sepoliaToken)));

        vm.deal(address(vault), 1e18);

        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));

        sepoliaToken.grantMintAndBurnRole(address(vault));

        registryModuleOwnerCustomSepolia = RegistryModuleOwnerCustom(
            sepoliaNetworkDetails.registryModuleOwnerCustomAddress
        );

        registryModuleOwnerCustomSepolia.registerAdminViaOwner(
            address(sepoliaToken)
        );

        tokenAdminRegistrySepolia = TokenAdminRegistry(
            sepoliaNetworkDetails.tokenAdminRegistryAddress
        );

        tokenAdminRegistrySepolia.acceptAdminRole(address(sepoliaToken));

        tokenAdminRegistrySepolia.setPool(
            address(sepoliaToken),
            address(sepoliaPool)
        );

        vm.stopPrank();

        // 2. Deploy Phase: Destination Chain (Arbitrum Sepolia)

        vm.selectFork(arbSepoliaFork);

        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(
            block.chainid
        );

        vm.startPrank(owner);

        arbSepoliaToken = new ReBaseToken();

        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );

        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));

        registryModuleOwnerArbitrum = RegistryModuleOwnerCustom(
            arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress
        );

        registryModuleOwnerArbitrum.registerAdminViaOwner(
            address(arbSepoliaToken)
        );

        tokenAdminRegistryArbitrum = TokenAdminRegistry(
            arbSepoliaNetworkDetails.tokenAdminRegistryAddress
        );

        tokenAdminRegistryArbitrum.acceptAdminRole(address(arbSepoliaToken));

        tokenAdminRegistryArbitrum.setPool(
            address(arbSepoliaToken),
            address(arbSepoliaPool)
        );

        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 forkId,
        TokenPool localPool,
        TokenPool remotePool,
        IReBaseToken remoteToken,
        Register.NetworkDetails memory remoteNetworkDetails
    ) public {
        vm.selectFork(forkId);

        vm.startPrank(owner);

        TokenPool.ChainUpdate[]
            memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        bytes[] memory remotePoolAddresses = new bytes[](1);

        remotePoolAddresses[0] = abi.encode(remotePool);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteNetworkDetails.chainSelector,
            remotePoolAddresses: remotePoolAddresses, // Match expected signature formatting
            remoteTokenAddress: abi.encode(address(remoteToken)),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false,
                capacity: 0,
                rate: 0
            })
        });

        uint64[] memory remoteChainSelectorsRemove = new uint64[](0);

        localPool.applyChainUpdates(remoteChainSelectorsRemove, chainsToAdd);

        vm.stopPrank();
    }

    // Stack optimized bridge caller leveraging internal struct references

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        ReBaseToken localToken,
        ReBaseToken remoteToken
    ) public {
        vm.selectFork(localFork);

        vm.startPrank(user);

        Client.EVMTokenAmount[]
            memory tokenToSendDetails = new Client.EVMTokenAmount[](1);

        Client.EVMTokenAmount memory tokenAmount = Client.EVMTokenAmount({
            token: address(localToken),
            amount: amountToBridge
        });

        tokenToSendDetails[0] = tokenAmount;

        IERC20(address(localToken)).approve(
            localNetworkDetails.routerAddress,
            amountToBridge
        );

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenToSendDetails,
            extraArgs: "",
            feeToken: localNetworkDetails.linkAddress
        });

        vm.stopPrank();

        ccipLocalSimulatorFork.requestLinkFromFaucet(
            user,
            IRouterClient(localNetworkDetails.routerAddress).getFee(
                remoteNetworkDetails.chainSelector,
                message
            )
        );

        vm.startPrank(user);

        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            IRouterClient(localNetworkDetails.routerAddress).getFee(
                remoteNetworkDetails.chainSelector,
                message
            )
        );

        uint256 balanceBeforeBridge = IERC20(address(localToken)).balanceOf(
            user
        );

        console.log("Local balance before Bridge: %d", balanceBeforeBridge);

        IRouterClient(localNetworkDetails.routerAddress).ccipSend(
            remoteNetworkDetails.chainSelector,
            message
        );

        uint256 sourceBalanceAfterBridge = IERC20(address(localToken))
            .balanceOf(user);

        console.log("Local balance after bridge: %d", sourceBalanceAfterBridge);

        assertEq(
            sourceBalanceAfterBridge,
            balanceBeforeBridge - amountToBridge
        );

        vm.stopPrank();

        vm.selectFork(remoteFork);

        vm.warp(block.timestamp + 900);

        uint256 initialArbBalance = IERC20(address(remoteToken)).balanceOf(
            user
        );

        console.log("Remote balance before bridge %d", initialArbBalance);

        vm.selectFork(localFork);
        
        ccipLocalSimulatorFork.switchChainAndRouteMessage(
            remoteFork
        );

        console.log(
            "Remote user interest rate %d",
            remoteToken.getUserInterestRate(user)
        );

        uint256 destBalance = IERC20(address(remoteToken)).balanceOf(user);

        console.log("Remote balance after bridge %d", destBalance);

        assertEq(destBalance, initialArbBalance + amountToBridge);
    }

    function testBridgeAllTokens() public {
        configureTokenPool(
            sepoliaFork,
            sepoliaPool,
            arbSepoliaPool,
            IReBaseToken(address(arbSepoliaToken)),
            arbSepoliaNetworkDetails
        );

        configureTokenPool(
            arbSepoliaFork,
            arbSepoliaPool,
            sepoliaPool,
            IReBaseToken(address(sepoliaToken)),
            sepoliaNetworkDetails
        );

        vm.selectFork(sepoliaFork);

        vm.deal(user, SEND_VALUE);

        vm.startPrank(user);

        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        console.log("Bridging %d tokens", SEND_VALUE);

        uint256 startBalance = IERC20(address(sepoliaToken)).balanceOf(user);

        assertEq(startBalance, SEND_VALUE);

        vm.stopPrank();

        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
    }
}
