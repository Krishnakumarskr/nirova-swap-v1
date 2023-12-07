//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface INirovaSwapCallback {
    function nirovaSwapMintCallback(uint256 amount0, uint256 amount1, bytes calldata data) external;
    function nirovaSwapSwapCallback(int256 amount0, int256 amount1, bytes calldata data) external;
}