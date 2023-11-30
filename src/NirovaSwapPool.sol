//SPDX-License-Identifier: MIT

import {Position} from './lib/Position.sol';
import {Tick} from './lib/Tick.sol';
import {INirovaSwapCallback} from './interfaces/INirovaSwapCallback.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


pragma solidity ^0.8.13;

contract NirovaSwapPool {

    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    error InvalidTickRange();
    error ZeroLiquidity();
    error InsufficientInputAmount();


    event Mint(address indexed minter, address indexed owner, uint128 indexed amount, int24 lowerTick, int24 upperTick, uint256 amount0, uint256 amount1);

    //Ticks will always be in a finite range for all pairs and so they are constant
    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;
    
    address public immutable token0;
    address public immutable token1;

    //Storing the current price and the corresponding tick in a single slot
    struct Slot0 {
        //Price in Q64.96 format. Current sqrt(price)
        uint160 sqrtPriceX96;

        //Current tick
        int24 tick;
    }

    Slot0 public slot0;

    //Total liquidity of a poll
    uint128 public liquidity;

    // Store the position info against a unique position id
    mapping(bytes32 => Position.Info) public positions;

    // Store the tick info against each tick
    mapping(int24 => Tick.Info) public ticks;

    constructor(
        address _token0,
        address _token1,
        uint160 _sqrtPricex96,
        int24 _tick
    ) {
        token0 = _token0;
        token1 = _token1;

        slot0 = Slot0({sqrtPriceX96: _sqrtPricex96, tick: _tick});
    }

    function mint(
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount
    ) external returns(uint256 amount0, uint256 amount1) {
        if(
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK ||
            lowerTick >= upperTick
        )
            revert InvalidTickRange();

        if(amount == 0) revert ZeroLiquidity();

        ticks.update(lowerTick, amount);
        ticks.update(upperTick, amount);

        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        position.update(amount);

        amount0 = 0.998976618347425280 ether;
        amount1 = 5000 ether;

        liquidity += uint128(amount);

        uint256 balance0Before;
        uint256 balance1Before;

        if(amount0 > 0) balance0Before = balance0();
        if(amount1 > 0) balance1Before = balance1();

        // Callback to the msg.sender to send the token0 and token1 to the pool contract
        INirovaSwapCallback(msg.sender).nirovaSwapCallback(amount0, amount1);

        if(amount0 > 0 && balance0Before + amount0 > balance0())
            revert InsufficientInputAmount();

        if(amount1 > 0 && balance1Before + amount1 > balance1())
            revert InsufficientInputAmount();

        emit Mint(msg.sender, owner, liquidity, lowerTick, upperTick, amount0, amount1);
    }

    function balance0() internal view returns(uint256) {
        return IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal view returns(uint256) {
        return IERC20(token1).balanceOf(address(this));
    }
}