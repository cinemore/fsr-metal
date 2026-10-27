// 派生自 AMD FidelityFX FSR 1.0，许可证见随包分发的 THIRD-PARTY.txt。
// 保留 FP32 近似常量、累加顺序与去振铃；本轮不使用 half 或融合 RCAS。
#include <metal_stdlib>
using namespace metal;

float fsrLowRcp(float value) { return as_type<float>(0x7ef07ebbu - as_type<uint>(value)); }
float fsrLowRsq(float value) { return as_type<float>(0x5f347d74u - (as_type<uint>(value) >> 1)); }
float fsrMediumRcp(float value) {
    float estimate = as_type<float>(0x7ef19fffu - as_type<uint>(value));
    return estimate * (-estimate * value + 2.0f);
}

float3 fsrRead(texture2d<float, access::read> input, int2 point) {
    int2 limit = int2(input.get_width(), input.get_height()) - 1;
    return input.read(uint2(clamp(point, int2(0), limit))).rgb;
}

float fsrLuma(float3 color) { return color.b * 0.5f + (color.r * 0.5f + color.g); }

void fsrDirection(thread float2& direction, thread float& length, float weight,
                  float a, float b, float c, float d, float e) {
    float dx = d - b;
    float lx = fsrLowRcp(max(abs(d - c), abs(c - b)));
    direction.x += dx * weight;
    lx = saturate(abs(dx) * lx);
    lx *= lx;
    length += lx * weight;
    float dy = e - a;
    float ly = fsrLowRcp(max(abs(e - c), abs(c - a)));
    direction.y += dy * weight;
    ly = saturate(abs(dy) * ly);
    ly *= ly;
    length += ly * weight;
}

void fsrTap(thread float3& color, thread float& weight, float2 offset,
            float2 direction, float2 length, float lobe, float clip, float3 tap) {
    float2 rotated = float2(offset.x * direction.x + offset.y * direction.y,
                            offset.x * (-direction.y) + offset.y * direction.x);
    rotated *= length;
    float distance = min(rotated.x * rotated.x + rotated.y * rotated.y, clip);
    float base = (2.0f / 5.0f) * distance - 1.0f;
    float window = lobe * distance - 1.0f;
    base *= base;
    window *= window;
    base = (25.0f / 16.0f) * base - (25.0f / 16.0f - 1.0f);
    float w = base * window;
    color += tap * w;
    weight += w;
}

kernel void fsrEasu(texture2d<float, access::read> input [[texture(0)]],
                    texture2d<float, access::write> output [[texture(1)]],
                    constant float4& mapping [[buffer(0)]],
                    uint2 point [[thread_position_in_grid]]) {
    if (point.x >= output.get_width() || point.y >= output.get_height()) return;
    float2 position = float2(point) * mapping.xy + mapping.zw;
    float2 origin = floor(position);
    float2 phase = position - origin;
    int2 p = int2(origin);
    float3 b = fsrRead(input, p + int2(0, -1));
    float3 c = fsrRead(input, p + int2(1, -1));
    float3 e = fsrRead(input, p + int2(-1, 0));
    float3 f = fsrRead(input, p);
    float3 g = fsrRead(input, p + int2(1, 0));
    float3 h = fsrRead(input, p + int2(2, 0));
    float3 i = fsrRead(input, p + int2(-1, 1));
    float3 j = fsrRead(input, p + int2(0, 1));
    float3 k = fsrRead(input, p + int2(1, 1));
    float3 l = fsrRead(input, p + int2(2, 1));
    float3 n = fsrRead(input, p + int2(0, 2));
    float3 o = fsrRead(input, p + int2(1, 2));
    float2 direction = 0;
    float length = 0;
    fsrDirection(direction, length, (1-phase.x)*(1-phase.y), fsrLuma(b), fsrLuma(e), fsrLuma(f), fsrLuma(g), fsrLuma(j));
    fsrDirection(direction, length, phase.x*(1-phase.y), fsrLuma(c), fsrLuma(f), fsrLuma(g), fsrLuma(h), fsrLuma(k));
    fsrDirection(direction, length, (1-phase.x)*phase.y, fsrLuma(f), fsrLuma(i), fsrLuma(j), fsrLuma(k), fsrLuma(n));
    fsrDirection(direction, length, phase.x*phase.y, fsrLuma(g), fsrLuma(j), fsrLuma(k), fsrLuma(l), fsrLuma(o));
    float2 square = direction * direction;
    float magnitude = square.x + square.y;
    bool zero = magnitude < 1.0f / 32768.0f;
    float reciprocal = fsrLowRsq(magnitude);
    reciprocal = zero ? 1.0f : reciprocal;
    direction.x = zero ? 1.0f : direction.x;
    direction *= reciprocal;
    length *= 0.5f;
    length *= length;
    float stretch = (direction.x*direction.x + direction.y*direction.y) * fsrLowRcp(max(abs(direction.x), abs(direction.y)));
    float2 anisotropy = float2(1 + (stretch - 1)*length, 1 - 0.5f*length);
    float lobe = 0.5f + ((1.0f/4.0f - 0.04f) - 0.5f)*length;
    float clip = fsrLowRcp(lobe);
    float3 lower = min(min(min(f, g), j), k);
    float3 upper = max(max(max(f, g), j), k);
    float3 sum = 0;
    float weight = 0;
    fsrTap(sum, weight, float2(0,-1)-phase, direction, anisotropy, lobe, clip, b);
    fsrTap(sum, weight, float2(1,-1)-phase, direction, anisotropy, lobe, clip, c);
    fsrTap(sum, weight, float2(-1,1)-phase, direction, anisotropy, lobe, clip, i);
    fsrTap(sum, weight, float2(0,1)-phase, direction, anisotropy, lobe, clip, j);
    fsrTap(sum, weight, float2(0,0)-phase, direction, anisotropy, lobe, clip, f);
    fsrTap(sum, weight, float2(-1,0)-phase, direction, anisotropy, lobe, clip, e);
    fsrTap(sum, weight, float2(1,1)-phase, direction, anisotropy, lobe, clip, k);
    fsrTap(sum, weight, float2(2,1)-phase, direction, anisotropy, lobe, clip, l);
    fsrTap(sum, weight, float2(2,0)-phase, direction, anisotropy, lobe, clip, h);
    fsrTap(sum, weight, float2(1,0)-phase, direction, anisotropy, lobe, clip, g);
    fsrTap(sum, weight, float2(1,2)-phase, direction, anisotropy, lobe, clip, o);
    fsrTap(sum, weight, float2(0,2)-phase, direction, anisotropy, lobe, clip, n);
    output.write(float4(min(upper, max(lower, sum * (1.0f / weight))), 1), point);
}

kernel void fsrRcas(texture2d<float, access::read> input [[texture(0)]],
                    texture2d<float, access::write> output [[texture(1)]],
                    constant float& strength [[buffer(0)]],
                    uint2 point [[thread_position_in_grid]]) {
    if (point.x >= output.get_width() || point.y >= output.get_height()) return;
    int2 p = int2(point);
    float3 b = fsrRead(input, p + int2(0,-1));
    float3 d = fsrRead(input, p + int2(-1,0));
    float3 e = fsrRead(input, p);
    float3 f = fsrRead(input, p + int2(1,0));
    float3 h = fsrRead(input, p + int2(0,1));
    float3 lower = min(min(min(b,d),f),h);
    float3 upper = max(max(max(b,d),f),h);
    float3 hitMin = min(lower,e) * (1.0f / (4.0f * upper));
    float3 hitMax = (1.0f - max(upper,e)) * (1.0f / (4.0f * lower - 4.0f));
    // 上游浮点 min/max 在零分母 NaN 时选择另一个操作数，不把全黑／全白改为特殊锐化分支。
    float3 lobes = fmax(-hitMin, hitMax);
    float lobe = fmax(-0.1875f, fmin(fmax(fmax(lobes.r,lobes.g),lobes.b),0.0f)) * strength;
    float reciprocal = fsrMediumRcp(4.0f*lobe+1.0f);
    output.write(float4((lobe*b+lobe*d+lobe*h+lobe*f+e)*reciprocal, 1), point);
}
