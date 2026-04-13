/*
    LumaBoost
    
    A ReShade shader that emulates hardware-level 
    EOTF boosting (Midtone Lifting) found on newer OLED monitors.
    
    This shader dynamically compensates for ABL (Auto Brightness Limiting) 
    by lifting midtones while strictly preserving peak highlights and blacks.
	
	Features:
    - Dynamic APL Trigger: Boosts brightness only when the screen gets bright.
    - Temporal Smoothing: Prevents flickering by gliding brightness changes.
    - Shadow Protection: Preserves inky blacks and infinite contrast.
    - Skin Tone Protection: Keeps character faces looking natural during boosts.
    - Saturation Recovery: Prevents "washout" in boosted areas.
*/

#include "ReShade.fxh"

// =============================================================================
// 1. SYSTEM DETECTION & CONSTANTS
// =============================================================================

#if BUFFER_COLOR_SPACE == 3 // HDR10 PQ
    #define CS_NAME "HDR10 (PQ)"
    #define LUMA_COEFF float3(0.2627, 0.6780, 0.0593)
#elif BUFFER_COLOR_SPACE == 2 // scRGB Linear
    #define CS_NAME "scRGB (Linear)"
    #define LUMA_COEFF float3(0.2627, 0.6780, 0.0593)
#else // SDR sRGB
    #define CS_NAME "SDR (sRGB)"
    #define LUMA_COEFF float3(0.2126, 0.7152, 0.0722)
#endif

// =============================================================================
// 2. UI CONTROLS
// =============================================================================

uniform int Info <
    ui_type = "radio"; ui_label = " "; ui_category = "0. System Info";
    ui_text = "Detected Format: " CS_NAME;
>;

uniform float APL_Threshold <
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "APL Trigger Threshold";
> = 0.25;

uniform float Boost <
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Max Boost Strength";
> = 1.0;

uniform float Boost_Ramp <
    ui_type = "slider"; ui_min = 1.0; ui_max = 20.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Boost Activation Sensitivity";
> = 10.0;

uniform float Smoothing_Speed <
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.99;
    ui_category = "1. Main Boost Settings";
    ui_label = "Temporal Smoothing";
> = 0.90;

uniform float Shadow_Protect <
    ui_type = "slider"; ui_min = 0.1; ui_max = 2.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Shadow Protect";
> = 1.0;

uniform bool Enable_Sat_Recover < ui_category = "2. Color Correction"; ui_label = "Enable Saturation Recovery"; > = true;
uniform float Sat_Recover < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "2. Color Correction"; ui_label = "Saturation Recovery Amount"; > = 0.15;

uniform bool Enable_Skin_Protect < ui_category = "3. Skin Protection"; ui_label = "Enable Skin Protection"; > = true;
uniform float Skin_Protect_Strength < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "3. Skin Protection"; ui_label = "Protection Strength"; > = 0.50;
uniform float Skin_Hue_Center < ui_type = "slider"; ui_min = 0.0; ui_max = 3.14; ui_category = "3. Skin Protection"; ui_label = "Hue Center"; > = 2.25;
uniform float Skin_Sensitivity < ui_type = "slider"; ui_min = 0.05; ui_max = 1.0; ui_category = "3. Skin Protection"; ui_label = "Mask Width"; > = 0.25;

uniform bool Debug_Skin < ui_category = "4. Debug Tools"; ui_label = "DEBUG: Show Skin Mask"; > = false;
uniform bool Show_Debug < ui_category = "4. Debug Tools"; ui_label = "Show Visual Stats"; > = false;

// =============================================================================
// 3. TEXTURES & SAMPLERS
// =============================================================================

texture texStats { Width = 32; Height = 32; Format = RGBA16F; };
sampler sStats { Texture = texStats; };
texture texStatsPrev { Width = 1; Height = 1; Format = RGBA16F; };
sampler sStatsPrev { Texture = texStatsPrev; };
texture texStatsCurr { Width = 1; Height = 1; Format = RGBA16F; };
sampler sStatsCurr { Texture = texStatsCurr; };

// =============================================================================
// 4. COLOR SCIENCE UTILITIES
// =============================================================================

float3 Decode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 // PQ
    float3 cp = pow(max(c, 0.0), 0.012683);
    return pow(max(cp - 0.8359375, 0.0) / (18.85156 - 18.6875 * cp), 6.27739);
#elif BUFFER_COLOR_SPACE == 2 // scRGB
    return c / 125.0; 
#else // SDR
    return pow(max(c, 0.0), 2.2);
#endif
}

float3 Encode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 // PQ
    float3 cp = pow(max(c, 0.0), 0.159301);
    return pow((0.8359375 + 18.85156 * cp) / (1.0 + 18.6875 * cp), 78.84375);
#elif BUFFER_COLOR_SPACE == 2 // scRGB
    return c * 125.0;
#else // SDR
    return pow(max(c, 0.0), 0.454545);
#endif
}

// =============================================================================
// 5. PROCESSING PASSES
// =============================================================================

// Pass 1: Local Grid Stats
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

// Pass 2: Global Stats & Temporal Smoothing
float4 PS_SmoothStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float avg = 0, mx = 0;
    for(int i=0; i<32; i++) for(int j=0; j<32; j++) {
        float2 s = tex2D(sStats, float2(i, j) / 32.0).xy;
        avg += s.x; mx = max(mx, s.y);
    }
    float2 last = tex2D(sStatsPrev, 0.5).xy;
    return float4(lerp(avg/1024.0, last.x, Smoothing_Speed), lerp(mx, last.y, Smoothing_Speed), 0, 1);
}

// Pass 3: Main LumaBoost
float4 PS_LumaBoost(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    const float4 base = tex2D(ReShade::BackBuffer, uv);
    const float2 stats = tex2D(sStatsCurr, 0.5).xy;
    const float trigger = saturate((stats.x - APL_Threshold) * Boost_Ramp);

    float3 linearC = Decode(base.rgb);
    const float oldY = dot(linearC, LUMA_COEFF);
    const float linearPeak = Decode(float3(stats.y, stats.y, stats.y)).r;

    // Skin Detection (Signal Space)
    float skinMask = 0.0;
    float3 signalC = (BUFFER_COLOR_SPACE == 2) ? saturate(base.rgb / 125.0) : base.rgb;
    
    if (Enable_Skin_Protect || Debug_Skin) {
        float sigCb = dot(signalC, float3(-0.1396, -0.3604, 0.5));
        float sigCr = dot(signalC, float3(0.5, -0.4598, -0.0402));
        float hue = atan2(sigCr, sigCb);
        float d = abs(hue - Skin_Hue_Center); if (d > 3.14159) d = 6.28318 - d;
        skinMask = saturate(1.0 - d / Skin_Sensitivity) * saturate(length(float2(sigCb, sigCr)) * 15.0);
    }

    float3 outColor = linearC;

    if (oldY < linearPeak && trigger > 0.0) {
        float pX = pow(max(oldY / max(linearPeak, 1e-6), 0.0), 0.45); 
        float finalBoost = Boost * (1.0 - (skinMask * Skin_Protect_Strength * Enable_Skin_Protect));
        
        float lift = finalBoost * trigger * pow(pX, Shadow_Protect * 2.0) * (1.0 - pX) * linearPeak;
        float newY = oldY + lift;

        // RGB Ratio scaling (Hue-Stable)
        float3 boostedC = linearC * (newY / max(oldY, 1e-6));

        // Perceptual Saturation Recovery
        if (Enable_Sat_Recover) {
            float satInt = (lift / max(linearPeak, 1e-6)) * Sat_Recover * 10.0;
            outColor = lerp(float3(newY, newY, newY), boostedC, 1.0 + satInt);
        } else {
            outColor = boostedC;
        }
    }

    if (Debug_Skin) outColor = lerp(outColor, float3(0.01, 0, 0.01), skinMask);

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

// Pass 4: Save Temporal State
float4 PS_SaveStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    return tex2D(sStatsCurr, 0.5);
}

// =============================================================================
// 6. PIPELINE DEFINITION
// =============================================================================

technique LumaBoost {
    pass { VertexShader = PostProcessVS; PixelShader = PS_CalcStats; RenderTarget = texStats; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SmoothStats; RenderTarget = texStatsCurr; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_LumaBoost; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SaveStats; RenderTarget = texStatsPrev; }
}
