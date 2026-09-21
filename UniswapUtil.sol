library UniswapUtil {
    function getSqrtRatioAtTick(int24 tick) internal pure returns (uint160 sqrtPriceX96) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= 887272, "TICK_BOUND");

        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb893cd21d25d20f02bca0664942f : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d4ffff215) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656832ef135) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c362) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db5) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6) >> 128;
        if (absTick & 0x50 != 0) ratio = (ratio * 0xff2ea64746aa0a8a3c577) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c46) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcff8) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf987a7253ac4131beb6f8) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xf3392b0822b700f5840c7) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0xa9f746462d870fdf8865d) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x31be135f97d08fd981231) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x5d6af8dedb8119669993) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        sqrtPriceX96 = uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    function getLiquidityForAmount0(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint256 amount0
    ) internal pure returns (uint128 liquidity) {
        if (sqrtRatioAX96 > sqrtRatioBX96) {
            (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
        }
        uint256 intermediate = mulDiv(sqrtRatioAX96, sqrtRatioBX96, 0x100000000000000000000000000000000);
        return uint128(mulDiv(amount0, intermediate, sqrtRatioBX96 - sqrtRatioAX96));
    }

    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }
        if (prod1 == 0) {
            require(denominator > 0);
            return prod0 / denominator;
        }
        require(denominator > prod1, "Overflow");
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }
        uint256 twos = denominator & (~denominator + 1);
        assembly {
            denominator := div(denominator, twos)
            prod0 := div(prod0, twos)
            twos := add(div(sub(0, twos), twos), 1)
        }
        assembly {
            prod0 := or(prod0, mul(prod1, twos))
        }
        uint256 inv = (3 * denominator) ^ 2;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        inv *= 2 - denominator * inv;
        result = prod0 * inv;
        return result;
    }
}
