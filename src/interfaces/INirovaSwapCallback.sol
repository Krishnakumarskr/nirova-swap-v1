//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

interface INirovaSwapCallback {
    function nirovaSwapCallback(uint256 amount0, uint256 amount1) external;
}