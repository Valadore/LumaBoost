/*
================================================================================
    LumaBoost - Professional EOTF & Brightness Compensation
================================================================================
    
    PURPOSE:
    This shader emulates high-end hardware logic to fight OLED ABL dimming.
    It dynamically lifts midtones while preserving peaks, blacks, and skin.

    FEATURES:
    - Format-Aware: Automatically adapts to SDR, HDR10 (PQ), and scRGB.
    - Sky ABL Bias: Advanced protection for Blue/Cyan hues to keep APL low.
    - Adaptive Saturation: Perceptual Color Volume protection.
    - Temporal Smoothing: Cinematic transitions to eliminate flickering.
    - Gain-Based Heatmap: Visualizes the literal percentage of light added.
================================================================================
*/

#include "ReShade.fxh"

// =============================================================================
// 1. SYSTEM DETECTION & CONSTANTS
// =============================================================================

#if BUFFER_COLOR_SPACE == 3 // HDR10 PQ (Uses BT.2020 Primaries)
    #define CS_NAME "HDR10 (PQ)"
    #define LUMA_COEFF float3(0.2627, 0.6780, 0.0593)
    #define CHROMA_B   float3(-0.1396, -0.3604, 0.5)
    #define CHROMA_R   float3(0.5, -0.4598, -0.0402)
#elif BUFFER_COLOR_SPACE == 2 // scRGB Linear (Uses BT.709 Primaries)
    #define CS_NAME "scRGB (Linear)"
    #define LUMA_COEFF float3(0.2126, 0.7152, 0.0722)
    #define CHROMA_B   float3(-0.1146, -0.3854, 0.5)
    #define CHROMA_R   float3(0.5, -0.4542, -0.0458)
#else // SDR sRGB (Uses BT.709 Primaries)
    #define CS_NAME "SDR (sRGB)"
    #define LUMA_COEFF float3(0.2126, 0.7152, 0.0722)
    #define CHROMA_B   float3(-0.1146, -0.3854, 0.5)
    #define CHROMA_R   float3(0.5, -0.4542, -0.0458)
#endif

// =============================================================================
// 2. UI CONTROLS (Defaults precisely centered on Sliders)
// =============================================================================

uniform int Info <
    ui_type = "radio"; ui_label = " "; ui_category = "0. System Info";
    ui_text = "Detected Format: " CS_NAME;
>;

uniform float APL_Threshold <
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.44;
    ui_category = "1. Main Boost Settings";
    ui_label = "APL Trigger Threshold";
    ui_tooltip = "Scene brightness required to trigger boost. Default: 0.22.";
> = 0.22;

uniform float Boost <
    ui_type = "slider"; ui_min = 0.0; ui_max = 3.6;
    ui_category = "1. Main Boost Settings";
    ui_label = "Max Boost Strength";
    ui_tooltip = "Intensity of the midtone lift. Default: 1.8.";
> = 1.8;

uniform float Boost_Ramp <
    ui_type = "slider"; ui_min = 0.0; ui_max = 8.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Boost Activation Sensitivity";
    ui_tooltip = "How fast boost reaches full power. Default: 4.0.";
> = 4.0;

uniform float Smoothing_Speed <
    ui_type = "slider"; ui_min = 0.7; ui_max = 1.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Temporal Smoothing";
    ui_tooltip = "Smooths brightness transitions. Default: 0.85.";
> = 0.85;

uniform float Shadow_Protect <
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.04;
    ui_category = "1. Main Boost Settings";
    ui_label = "Shadow Protect";
    ui_tooltip = "Keeps deep blacks dark. Default: 1.02.";
> = 1.02;

uniform float Highlight_Protect <
    ui_type = "slider"; ui_min = 0.0; ui_max = 5.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Highlight Protect";
    ui_tooltip = "Protects bright areas like sky. Default: 2.5.";
> = 2.5;

uniform bool Enable_Sky_Bias <
    ui_category = "1. Main Boost Settings";
    ui_label = "Enable Sky ABL Bias";
    ui_tooltip = "Applies extra protection to Blue/Cyan hues.";
> = true;

uniform float Sky_Bias <
    ui_type = "slider"; ui_min = 0.0; ui_max = 20.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Sky Bias Strength";
    ui_tooltip = "How hard to pinch the boost for blue skies. Default: 10.0.";
> = 10.0;

uniform bool Enable_Sat_Recover < ui_category = "2. Color Correction"; ui_label = "Enable Saturation Recovery"; > = true;
uniform bool Enable_Adaptive_Sat < ui_category = "2. Color Correction"; ui_label = "Use Adaptive Scaling"; > = true;

uniform float Sat_Recover < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; 
    ui_category = "2. Color Correction"; 
    ui_label = "Saturation Recovery Amount"; 
    ui_tooltip = "Restores color depth in boosted areas. Default: 0.50.";
> = 0.50;

uniform float Sat_Threshold <
    ui_type = "slider"; ui_min = 1.0; ui_max = 30.0;
    ui_category = "2. Color Correction";
    ui_label = "Adaptive Sat. Sensitivity";
    ui_tooltip = "Aggressiveness of Color Volume protection. Default: 15.0.";
> = 15.0;

uniform bool Enable_Skin_Protect < ui_category = "3. Skin Protection"; ui_label = "Enable Skin Protection"; > = true;
uniform float Skin_Protect_Strength < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "3. Skin Protection"; ui_label = "Protection Strength"; > = 0.50;
uniform float Skin_Hue_Center < ui_type = "slider"; ui_min = 1.36; ui_max = 3.14; ui_category = "3. Skin Protection"; ui_label = "Hue Center"; > = 2.25;
uniform float Skin_Sensitivity < ui_type = "slider"; ui_min = 0.0; ui_max = 0.34; ui_category = "3. Skin Protection"; ui_label = "Mask Width"; > = 0.17;

uniform bool Debug_Skin < ui_category = "4. Debug Tools"; ui_label = "DEBUG: Show Skin Mask"; > = false;
uniform bool Debug_Heatmap < ui_category = "4. Debug Tools"; ui_label = "DEBUG: Show Boost Heatmap"; > = false;
uniform bool Show_Debug < ui_category = "4. Debug Tools"; ui_label = "Show Visual Stats"; > = false;

// =============================================================================
// 3. STORAGE & COLOR ENGINE
// =============================================================================

texture texStats { Width = 32; Height = 32; Format = RGBA16F; };
sampler sStats { Texture = texStats; };
texture texStatsPrev { Width = 1; Height = 1; Format = RGBA16F; };
sampler sStatsPrev { Texture = texStatsPrev; };
texture texStatsCurr { Width = 1; Height = 1; Format = RGBA16F; };
sampler sStatsCurr { Texture = texStatsCurr; };

float3 Decode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 
    float3 cp = pow(max(c, 0.0), 0.012683);
    return pow(max((cp - 0.8359375) / (18.85156 - 18.6875 * cp), 0.0), 6.27739);
#elif BUFFER_COLOR_SPACE == 2 
    return c / 125.0; 
#else 
    return pow(max(c, 0.0), 2.2);
#endif
}

float3 Encode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 
    float3 cp = pow(max(c, 0.0), 0.159301);
    return pow(max((0.8359375 + 18.85156 * cp) / (1.0 + 18.6875 * cp), 0.0), 78.84375);
#elif BUFFER_COLOR_SPACE == 2 
    return c * 125.0; 
#else 
    return pow(max(c, 0.0), 0.454545);
#endif
}

// =============================================================================
// 4. SHADER PASSES
// =============================================================================

float4 PS_CalcStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float avg = 0, mx = 0;
    [unroll] for(int i=0; i<4; i++) [unroll] for(int j=0; j<4; j++) {
        float3 c = tex2D(ReShade::BackBuffer, uv + (float2(i,j)/4.0-0.5)*float2(1.0/32.0, 1.0/32.0)).rgb;
        #if BUFFER_COLOR_SPACE == 2 
            c = saturate(c / 125.0);
        #endif
        float l = max(c.r, max(c.g, c.b));
        avg += l; mx = max(mx, l);
    }
    return float4(avg/16.0, mx, 0, 1);
}

float4 PS_SmoothStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float avg = 0, mx = 0;
    for(int i=0; i<32; i++) for(int j=0; j<32; j++) {
        float2 s = tex2D(sStats, float2(i, j) / 32.0).xy;
        avg += s.x; mx = max(mx, s.y);
    }
    float2 last = tex2D(sStatsPrev, 0.5).xy;
    return float4(lerp(avg/1024.0, last.x, Smoothing_Speed), lerp(mx, last.y, Smoothing_Speed), 0, 1);
}

float4 PS_LumaBoost(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    const float4 base = tex2D(ReShade::BackBuffer, uv);
    const float2 stats = tex2D(sStatsCurr, 0.5).xy;
    const float trigger = saturate((stats.x - APL_Threshold) * Boost_Ramp);

    float3 linearC = Decode(base.rgb);
    const float oldY = dot(linearC, LUMA_COEFF);
    const float linearPeak = Decode(float3(stats.y, stats.y, stats.y)).r;

    float3 signalC = (BUFFER_COLOR_SPACE == 2) ? saturate(base.rgb / 125.0) : base.rgb;
    float sigCb = dot(signalC, CHROMA_B);
    float sigCr = dot(signalC, CHROMA_R);
    float chroma = length(float2(sigCb, sigCr));
    float hue = atan2(sigCr, sigCb);

    // 1. Skin Mask
    float skinMask = 0.0;
    if (Enable_Skin_Protect || Debug_Skin) {
        float d = abs(hue - Skin_Hue_Center); if (d > 3.14159) d = 6.28318 - d;
        skinMask = saturate(1.0 - d / max(Skin_Sensitivity, 0.01)) * saturate(chroma * 15.0);
    }

    // 2. Sky Mask (Targeting Blue/Cyan ~ -0.5 radians)
    float skyMask = 0.0;
    if (Enable_Sky_Bias) {
        float skyDist = abs(hue - (-0.5)); if (skyDist > 3.14159) skyDist = 6.28318 - skyDist;
        skyMask = saturate(1.0 - skyDist / 0.4) * saturate(chroma * 10.0);
    }

    float3 outColor = linearC;
    float gainFactor = 0.0;

    if (oldY < linearPeak) {
        float pX = pow(max(oldY / max(linearPeak, 1e-6), 0.0), 0.45); 
        float dynHighlightProt = Highlight_Protect + (skyMask * Sky_Bias * Enable_Sky_Bias);
        float hump = pow(max(pX, 0.0), Shadow_Protect * 2.0) * pow(max(1.0 - pX, 0.0), dynHighlightProt * 2.0);
        
        float finalBoost = Boost * (1.0 - (skinMask * Skin_Protect_Strength * Enable_Skin_Protect));
        float lift = finalBoost * trigger * hump * linearPeak;
        
        gainFactor = lift / max(oldY, 1e-6); 
        float newY = oldY + lift;
        float3 boostedC = linearC * (newY / max(oldY, 1e-6));

        if (Enable_Sat_Recover && trigger > 0.0) {
            float satInt = (lift / max(linearPeak, 1e-6)) * Sat_Recover * 10.0;
            if (Enable_Adaptive_Sat) satInt *= saturate(1.0 - chroma * Sat_Threshold);
            outColor = lerp(float3(newY, newY, newY), boostedC, 1.0 + satInt);
        } else {
            outColor = boostedC;
        }
    }

    if (Debug_Skin) outColor = lerp(outColor, float3(0.01, 0, 0.01), skinMask);

    if (Debug_Heatmap) {
        float v = gainFactor / max(Boost, 1e-6);
        float3 heat = 0;
        heat = lerp(float3(0,0,0),       float3(0,0,0.01),    saturate(v * 5.0));
        heat = lerp(heat,                float3(0,0.01,0.01), saturate(v * 5.0 - 1.0));
        heat = lerp(heat,                float3(0,0.01,0),    saturate(v * 5.0 - 2.0));
        heat = lerp(heat,                float3(0.01,0.01,0), saturate(v * 5.0 - 3.0));
        heat = lerp(heat,                float3(0.01,0,0),    saturate(v * 5.0 - 4.0));
        outColor = heat;
    }

    if (Show_Debug) {
        if (uv.y < 0.02) {
            if (uv.x < stats.x) outColor = float3(0, 0.01, 0);
            if (abs(uv.x - APL_Threshold) < 0.001) outColor = float3(0.015, 0, 0);
        }
        if (uv.y > 0.022 && uv.y < 0.042 && uv.x < stats.y) outColor = float3(0, 0.002, 0.01);
        if (uv.y > 0.044 && uv.y < 0.064 && uv.x < (trigger * Boost / 4.0)) outColor = float3(0.01, 0.005, 0);
    }

    return float4(Encode(outColor), base.a);
}

float4 PS_SaveStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    return tex2D(sStatsCurr, 0.5);
}

// =============================================================================
// 5. PIPELINE DEFINITION
// =============================================================================

technique LumaBoost {
    pass { VertexShader = PostProcessVS; PixelShader = PS_CalcStats; RenderTarget = texStats; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SmoothStats; RenderTarget = texStatsCurr; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_LumaBoost; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SaveStats; RenderTarget = texStatsPrev; }
}
