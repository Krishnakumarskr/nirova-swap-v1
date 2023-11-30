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

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool shouldTransferInCallback;
        bool mintLiqudity;
    }

    function setUp() public {
        token0 = new MintableERC20("Ether", "ETH");
        token1 = new MintableERC20("USDC", "USDC");
    }

    function setupTestCase(TestCaseParams memory params) internal returns(uint256 poolBalance0, uint256 poolBalance1) {

        token0.mint(params.wethBalance);
        token1.mint(params.usdcBalance);

        pool = new NirovaSwapPool(
            address(token0),
            address(token1),
            params.currentSqrtP,
            params.currentTick
        );

        shouldTransferInCallback = params.shouldTransferInCallback;

        if(params.mintLiqudity) {
            (poolBalance0, poolBalance1) = pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity);
        }
    }

    function nirovaSwapCallback(uint256 amount0, uint256 amount1) public {
        if (shouldTransferInCallback) {
            token0.transfer(msg.sender, amount0);
            token1.transfer(msg.sender, amount1);
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
            mintLiqudity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);

        uint256 expectedAmount0 = 0.998976618347425280 ether;
        uint256 expectedAmount1 = 5000 ether;

        assertEq(poolBalance0, expectedAmount0, "incorrect tokne0 deposited");
        assertEq(poolBalance1, expectedAmount1, "incorrect token1 deposited");

        assertEq(token0.balanceOf(address(pool)), expectedAmount0);
        assertEq(token1.balanceOf(address(pool)), expectedAmount1);

        bytes32 positionKey = keccak256(
            abi.encodePacked(address(this), params.lowerTick, params.upperTick)
        );
        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity);

        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(params.lowerTick);
        assertTrue(tickInitialized);
        assertEq(tickLiquidity, params.liquidity);

        (tickInitialized, tickLiquidity) = pool.ticks(params.upperTick);
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
}