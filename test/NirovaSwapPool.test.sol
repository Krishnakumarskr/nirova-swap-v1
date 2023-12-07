//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {MintableERC20} from "./mocks/MintableERC20.sol";
import {NirovaSwapPool} from "../src/NirovaSwapPool.sol";
import {console2} from "forge-std/console2.sol";

contract NirovaSwapTest is Test {
    MintableERC20 token0;
    MintableERC20 token1;
    NirovaSwapPool pool;
    bool shouldTransferInCallback;
    bool shouldTransferInSwapCallback;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool shouldTransferInCallback;
        bool shouldTransferInSwapCallback;
        bool mintLiqudity;
    }

    function setUp() public {
        token0 = new MintableERC20("Ether", "ETH");
        token1 = new MintableERC20("USDC", "USDC");
    }

    function setupTestCase(TestCaseParams memory params) internal returns(uint256 poolBalance0, uint256 poolBalance1) {

        token0.mint(address(this), params.wethBalance);
        token1.mint(address(this), params.usdcBalance);

        pool = new NirovaSwapPool(
            address(token0),
            address(token1),
            params.currentSqrtP,
            params.currentTick
        );

        shouldTransferInCallback = params.shouldTransferInCallback;
        shouldTransferInSwapCallback = params.shouldTransferInSwapCallback;

        if(params.mintLiqudity) {
            token0.approve(address(this), params.wethBalance);
            token1.approve(address(this), params.usdcBalance);
            NirovaSwapPool.CallbackData memory extra = NirovaSwapPool
                .CallbackData({
                    token0: address(token0),
                    token1: address(token1),
                    payer: address(this)
                });
            (poolBalance0, poolBalance1) = pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity, abi.encode(extra));
        }
    }

    function nirovaSwapMintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        if (shouldTransferInCallback) {
                NirovaSwapPool.CallbackData memory extra = abi.decode(data,  (NirovaSwapPool.CallbackData));

                MintableERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
                MintableERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
        }
    } 

    function nirovaSwapSwapCallback(int256 amount0, int256 amount1, bytes calldata data) public {
        if (shouldTransferInSwapCallback) {
            NirovaSwapPool.CallbackData memory extra = abi.decode(data,  (NirovaSwapPool.CallbackData));

            if(amount0 > 0) 
                MintableERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint256(amount0));
            
            if(amount1 > 0)
                MintableERC20(extra.token1).transferFrom(extra.payer, msg.sender, uint256(amount1));
            }
    } 

    function testMintSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            shouldTransferInCallback: true,
            shouldTransferInSwapCallback: true,
            mintLiqudity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 expectedAmount0 = 0.998833192822975409 ether;
        uint256 expectedAmount1 = 4999.187247111820044641 ether;

        assertEq(poolBalance0, expectedAmount0, "incorrect tokne0 deposited");
        assertEq(poolBalance1, expectedAmount1, "incorrect token1 deposited");

        assertEq(token0.balanceOf(address(pool)), expectedAmount0);
        assertEq(token1.balanceOf(address(pool)), expectedAmount1);

        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), params.lowerTick, params.upperTick)
        );
        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity);

        (bool tickInitialized, uint128 tickLiquidity, ) = pool.ticks(params.lowerTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (tickInitialized, tickLiquidity, ) = pool.ticks(params.upperTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(
            sqrtPriceX96,
            5602277097478614198912276234240,
            "invalid current sqrtP"
        );
        assertEq(tick, 85176, "invalid current tick");
        assertEq(
            pool.liquidity(),
            1517882343751509868544,
            "invalid current liquidity"
        );
    }

    function testSwapSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            shouldTransferInCallback: true,
            shouldTransferInSwapCallback: true,
            mintLiqudity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        token1.mint(address(this), 42 ether);
        token1.approve(address(this), 42 ether);
        uint256 balance0Before = token0.balanceOf(address(this));

        int256 balance1Before = int256(token1.balanceOf(address(this)));

        NirovaSwapPool.CallbackData memory extra = NirovaSwapPool.CallbackData({
            token0: address(token0),
            token1: address(token1),
            payer: address(this)
        });

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(address(this), false, 42 ether, abi.encode(extra));

        assertEq(amount0Delta, -0.008396714242162445 ether, "invalid ETH out");
        assertEq(amount1Delta, 42 ether, "invalid USDC in");

        assertEq(
            token0.balanceOf(address(this)),
            uint256(balance0Before + uint256(-amount0Delta)),
            "invalid user ETH balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            uint256(balance1Before - amount1Delta),
            "invalid user USDC balance"
        );

        assertEq(
            token0.balanceOf(address(pool)),
            uint256(int256(poolBalance0) + amount0Delta),
            "invalid pool ETH balance"
        );
        assertEq(
            token1.balanceOf(address(pool)),
            uint256(int256(poolBalance1) + amount1Delta),
            "invalid pool USDC balance"
        );

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(
            sqrtPriceX96,
            5604469350942327889444743441197,
            "invalid current sqrtP"
        );
        assertEq(tick, 85184, "invalid current tick");
        assertEq(
            pool.liquidity(),
            1517882343751509868544,
            "invalid current liquidity"
        );
    }

    function testInvalidInput() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            shouldTransferInCallback: true,
            shouldTransferInSwapCallback: false,
            mintLiqudity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        vm.expectRevert(NirovaSwapPool.InsufficientInputAmount.selector);
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(address(this), false, 42 ether, "");

    }

    
}