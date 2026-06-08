//SPD-license-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract ConfigPoolScript is Script {
    
    function run(
        address localPool,
        address remotePool,
        uint64 chainSelector,
        address remotetoken,
        bool outboundRateLimiterisEnabled,
        bool inboundRateLimiterisEnabled,
        uint128 inboundRateLimiterRate,
        uint128 outboundRateLimiterRate,
        uint128 inboundRateLimiterCapacity,
        uint128 outboundRateLimiterCapasity
        ) public {
            vm.startBroadcast();
            bytes[] memory remotePoolAddress = new bytes[](1);
            remotePoolAddress[0] = abi.encode(remotePool);

            bytes memory remoteTokenAddress = abi.encode(remotetoken);

            TokenPool.ChainUpdate[] memory chiansToAdd = new  TokenPool.ChainUpdate[](1);

            chiansToAdd[0] = TokenPool.ChainUpdate({
                remoteChainSelector: chainSelector,
                remotePoolAddresses: remotePoolAddress,
                remoteTokenAddress: remoteTokenAddress,
                outboundRateLimiterConfig: RateLimiter.Config({
                    isEnabled: outboundRateLimiterisEnabled,
                    capacity: outboundRateLimiterCapasity,
                    rate: outboundRateLimiterRate
                }),
                inboundRateLimiterConfig: RateLimiter.Config({
                    isEnabled: inboundRateLimiterisEnabled,
                    capacity: inboundRateLimiterCapacity,
                    rate: inboundRateLimiterRate
                })
            });

            TokenPool(localPool).applyChainUpdates(
                new uint64[](0),
                chiansToAdd
            );
            vm.stopBroadcast();
    } 
}
