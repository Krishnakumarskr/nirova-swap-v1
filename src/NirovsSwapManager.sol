//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {NirovaSwapPool} from './NirovaSwapPool.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract NirovaSwapManager {

    function mint(
        address poolAddress_,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity,
        bytes calldata data
    ) public {
        NirovaSwapPool(poolAddress_).mint(
            msg.sender,
            lowerTick,
            upperTick,
            liquidity,
            data
        );
    }

    function swap(address poolAddress_, bool zeroForOne, uint256 amountSpecified, bytes calldata data) public {
        NirovaSwapPool(poolAddress_).swap(msg.sender, zeroForOne, amountSpecified, data);
    }

    function nirovaSwapMintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external {
        NirovaSwapPool.CallbackData memory extra = abi.decode(data,  (NirovaSwapPool.CallbackData));

        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }

    function nirovaSwapSwapCallback(int256 amount0, int256 amount1, bytes calldata data) external {
        NirovaSwapPool.CallbackData memory extra = abi.decode(data,  (NirovaSwapPool.CallbackData));

        if(amount0 > 0) 
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint256(amount0));
        
        if(amount1 > 0)
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, uint256(amount1));
    }

}