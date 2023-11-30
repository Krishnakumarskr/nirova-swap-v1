//SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

library Position {

    struct Info {
        uint128 liquidity;
    }

    function get(
        mapping(bytes32 => Position.Info) storage self,
        address owner,
        int24 lowerTick,
        int24 upperTick
    ) internal view returns(Position.Info storage position) {
        position = self[
            keccak256(abi.encodePacked(owner, lowerTick, upperTick))
        ];
    }

    function update(
        Info storage self,
        uint128 liquidity
    ) internal {
        uint128 liquidityBefore = self.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidity;

        self.liquidity = liquidityAfter;
    }
}