//SPDX-License-Identifier: MIT

import {Position} from './lib/Position.sol';
import {Tick} from './lib/Tick.sol';
import {INirovaSwapCallback} from './interfaces/INirovaSwapCallback.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TickBitmap} from './lib/TickBitmap.sol';
import {Math} from './lib/Math.sol';
import {TickMath} from './lib/TickMath.sol';
import {SwapMath} from './lib/SwapMath.sol';
import {console2} from 'forge-std/console2.sol';
import {LiquidityMath} from './lib/LiquidityMath.sol';


pragma solidity ^0.8.13;

contract NirovaSwapPool {

    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for Position.Info;

    error InvalidTickRange();
    error ZeroLiquidity();
    error InsufficientInputAmount();
    error NotEnoughLiquidity();


    event Mint(address indexed minter, address indexed owner, uint128 indexed amount, int24 lowerTick, int24 upperTick, uint256 amount0, uint256 amount1);
    event Swap(address indexed swapper, address indexed receipient, uint256 indexed amount0, uint256 amount1, uint160 price, int24 tick, uint128 liqudity);

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

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }
    // Swap state to track amount remaining on every iteration of swap
    struct SwapState {
        uint256 amountSpecifiedRemaining;
        uint256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
        uint128 liquidity;
    }

    //It maintains current swap state
    struct StepState {
        uint160 sqrtPriceStartX96;
        int24 nextTick;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        bool initialized;
    }

    Slot0 public slot0;

    //Total liquidity of a poll
    uint128 public liquidity;

    // Store the position info against a unique position id
    mapping(bytes32 => Position.Info) public positions;

    // Store the tick info against each tick
    mapping(int24 => Tick.Info) public ticks;

    //Storing the wordPos and wordValue
    mapping(int16 => uint256) public tickBitmap;

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
        uint128 amount,
        bytes calldata data
    ) external returns(uint256 amount0, uint256 amount1) {
        if(
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK ||
            lowerTick >= upperTick
        )
            revert InvalidTickRange();

        if(amount == 0) revert ZeroLiquidity();

        bool flippedLower = ticks.update(lowerTick, int128(amount), false);
        bool flippedUpper = ticks.update(upperTick, int128(amount), true);

        if(flippedLower) tickBitmap.flipTick(lowerTick, 1);
        if(flippedUpper) tickBitmap.flipTick(upperTick, 1);

        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        position.update(amount);

        Slot0 memory _slot0 = slot0;

        if(_slot0.tick < lowerTick) {
            amount0 = Math.calcAmount0Delta(TickMath.getSqrtRatioAtTick(lowerTick), TickMath.getSqrtRatioAtTick(upperTick), amount);
        }
        else if(_slot0.tick < upperTick) {
            amount0 = Math.calcAmount0Delta(TickMath.getSqrtRatioAtTick(_slot0.tick), TickMath.getSqrtRatioAtTick(upperTick), amount);
            amount1 = Math.calcAmount1Delta(TickMath.getSqrtRatioAtTick(_slot0.tick), TickMath.getSqrtRatioAtTick(lowerTick), amount);

            liquidity += uint128(amount);
        }
        else {
            amount1 = Math.calcAmount1Delta(TickMath.getSqrtRatioAtTick(lowerTick), TickMath.getSqrtRatioAtTick(lowerTick), amount);
        }

        uint256 balance0Before;
        uint256 balance1Before;

        if(amount0 > 0) balance0Before = balance0();
        if(amount1 > 0) balance1Before = balance1();

        // Callback to the msg.sender to send the token0 and token1 to the pool contract
        INirovaSwapCallback(msg.sender).nirovaSwapMintCallback(amount0, amount1, data);

        if(amount0 > 0 && balance0Before + amount0 > balance0())
            revert InsufficientInputAmount();

        if(amount1 > 0 && balance1Before + amount1 > balance1())
            revert InsufficientInputAmount();

        emit Mint(msg.sender, owner, liquidity, lowerTick, upperTick, amount0, amount1);
    }

    function swap(
        address recipient, 
        bool zeroForOne,
        uint256 amountSpecified,
        bytes calldata data)
        external
        returns(int256 amount0, int256 amount1) 
    {
        Slot0 memory slot0_ = slot0;
        uint128 liquidity_ = liquidity;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0_.sqrtPriceX96,
            tick: slot0_.tick,
            liquidity: liquidity_
        });

        while(state.amountSpecifiedRemaining > 0) {
            StepState memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.nextTick, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                1,
                zeroForOne
            );

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            (state.sqrtPriceX96, step.amountIn, step.amountOut) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                step.sqrtPriceNextX96,
                liquidity,
                state.amountSpecifiedRemaining
            );

            state.amountSpecifiedRemaining -= step.amountIn;
            state.amountCalculated += step.amountOut;

            if(state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if(step.initialized) {

                    int128 liquidityDelta = ticks.cross(step.nextTick);
                    if(zeroForOne) liquidityDelta = -liquidityDelta;

                    state.liquidity = LiquidityMath.addLiquidity(
                        state.liquidity,
                        liquidityDelta
                    );

                    if(state.liquidity == 0) revert NotEnoughLiquidity();
                }
                state.tick = zeroForOne ? step.nextTick - 1 : step.nextTick;
            } else {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
            
        }

        if (state.tick != slot0_.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        }

        if (liquidity_ != state.liquidity) liquidity = state.liquidity;

        (amount0, amount1) = zeroForOne
            ? (
                int256(amountSpecified - state.amountSpecifiedRemaining),
                -int256(state.amountCalculated)
            )
            : (
                -int256(state.amountCalculated),
                int256(amountSpecified - state.amountSpecifiedRemaining)
            );

        if (zeroForOne) {
            IERC20(token1).transfer(recipient, uint256(-amount1));

            uint256 balance0Before = balance0();
            INirovaSwapCallback(msg.sender).nirovaSwapSwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance0Before + uint256(amount0) > balance0())
                revert InsufficientInputAmount();
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            INirovaSwapCallback(msg.sender).nirovaSwapSwapCallback(
                amount0,
                amount1,
                data
            );
            if (balance1Before + uint256(amount1) > balance1())
                revert InsufficientInputAmount();
        }

        emit Swap(msg.sender, recipient, uint256(-amount0), uint256(amount1), slot0.sqrtPriceX96, slot0.tick, liquidity);
    }

    function balance0() internal view returns(uint256) {
        return IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal view returns(uint256) {
        return IERC20(token1).balanceOf(address(this));
    }
}