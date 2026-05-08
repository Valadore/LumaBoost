/*
================================================================================
    LumaBoost - Professional EOTF & Brightness Compensation
================================================================================
    
    PURPOSE:
    A professional display-hardware emulator designed to counteract OLED ABL.
    It dynamically lifts midtones when the screen dims, preserving the intended
    High Dynamic Range (HDR) experience.

    MODE SWITCHING (IMPORTANT):
    This shader uses Preprocessor Logic for maximum DX12 compatibility.
    1. Scroll to the BOTTOM of the ReShade 'Home' tab.
    2. Find 'Preprocessor Definitions'.
    3. Set TRIGGER_MODE to 0 for Standard Mode or 1 for ABL Curve Mode.
================================================================================
*/

#ifndef TRIGGER_MODE
    #define TRIGGER_MODE 1 
#endif

#if TRIGGER_MODE == 1
    #define MODE_STR "ABL Curve Model"
#else
    #define MODE_STR "Standard Threshold"
#endif

#include "ReShade.fxh"

// =============================================================================
// 1. SYSTEM DETECTION & CONSTANTS
// =============================================================================

#if BUFFER_COLOR_SPACE == 3 // HDR10 PQ
    #define CS_NAME "HDR10 (PQ)"
    #define LUMA_COEFF float3(0.2627, 0.6780, 0.0593)
    #define CHROMA_B   float3(-0.1396, -0.3604, 0.5)
    #define CHROMA_R   float3(0.5, -0.4598, -0.0402)
#elif BUFFER_COLOR_SPACE == 2 // scRGB Linear
    #define CS_NAME "scRGB (Linear)"
    #define LUMA_COEFF float3(0.2126, 0.7152, 0.0722)
    #define CHROMA_B   float3(-0.1146, -0.3854, 0.5)
    #define CHROMA_R   float3(0.5, -0.4542, -0.0458)
#else // SDR sRGB
    #define CS_NAME "SDR (sRGB)"
    #define LUMA_COEFF float3(0.2126, 0.7152, 0.0722)
    #define CHROMA_B   float3(-0.1146, -0.3854, 0.5)
    #define CHROMA_R   float3(0.5, -0.4542, -0.0458)
#endif

// =============================================================================
// 2. UI CONTROLS
// =============================================================================

uniform int Info <
    ui_type = "radio"; ui_label = " "; ui_category = "0. System Info";
    ui_text = "Format: " CS_NAME "\nMode: " MODE_STR;
    ui_tooltip = "LumaBoost automatically adjusts internal coefficients based on the detected format. To change modes, edit TRIGGER_MODE at the bottom of the ReShade Home tab.";
>;

// --- MODE 0: STANDARD (Visible only when TRIGGER_MODE is 0) ---

#if TRIGGER_MODE == 0
uniform float Standard_Boost <
    ui_type = "slider"; ui_min = 0.0; ui_max = 6.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Boost Strength";
    ui_tooltip = "The intensity of the lift. (Default: 3.0).";
> = 3.0;

uniform float APL_Threshold <
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.44;
    ui_category = "1. Main Boost Settings";
    ui_label = "APL Threshold";
    ui_tooltip = "Scene brightness required to trigger the boost. (Default 0.22).";
> = 0.22;

uniform float Boost_Ramp <
    ui_type = "slider"; ui_min = 0.0; ui_max = 7.948;
    ui_category = "1. Main Boost Settings";
    ui_label = "Boost Sensitivity";
    ui_tooltip = "How fast the boost reaches full power after passing the threshold. (Default 3.974).";
> = 3.974;
#endif

// --- MODE 1: ABL CURVE (Visible only when TRIGGER_MODE is 1) ---

#if TRIGGER_MODE == 1
uniform float ABL_Boost <
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Compensation Strength";
    ui_tooltip = "Scaling factor for the monitor model. 1.0 (Default) matches panel dimming exactly.";
> = 1.0;

uniform bool Show_Data_Points <
    ui_category = "2. Monitor ABL Data Points";
    ui_label = "EDIT CALIBRATION DATA";
    ui_category_toggle = true;
    ui_tooltip = "Unfold this only to enter measured nit values for your specific panel.";
> = false;

uniform float P001 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = "1% Window capability (Target)"; ui_tooltip = "The 1% window peak is used as the master target for all other window sizes."; > = 994.0;
uniform float P002 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = " 2% Window capability"; > = 943.0;
uniform float P005 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = " 5% Window capability"; > = 718.0;
uniform float P010 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = " 10% Window capability"; > = 451.0;
uniform float P025 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = " 25% Window capability"; > = 361.0;
uniform float P050 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = " 50% Window capability"; > = 303.0;
uniform float P075 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = " 75% Window capability"; > = 273.0;
uniform float P100 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = " 100% Window capability"; > = 258.0;
#endif

// --- ADVANCED QUALITY & PROTECTION ---

uniform bool Enable_Advanced <
    ui_category = "3. Advanced Quality & Protection";
    ui_label = "SHOW ADVANCED SETTINGS";
    ui_category_toggle = true;
    ui_tooltip = "Hides or shows detailed math controls for shadows, color volume, and stability.";
> = false;

uniform float Smoothing_Speed < 
    ui_type = "slider"; ui_min = 0.9; ui_max = 1.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Temporal Smoothing"; 
    ui_tooltip = "Glides brightness changes over time to prevent flickering. (Default 0.98).";
> = 0.98;

uniform float Specular_Immunity < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Specular Immunity"; 
    ui_tooltip = "Prevents tiny bright glints from suppressing the global world boost. (Default 0.50).";
> = 0.50;

uniform bool Enable_Black_Anchor < 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Enable Black Floor Tracking"; 
    ui_tooltip = "Detects the dimmest pixel in the frame to ensure boost starts there, preserving contrast.";
> = true;

uniform float Black_Anchor_Bias < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.13; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Black Floor Offset"; 
    ui_tooltip = "Moves the 'Zero Boost' zone deeper into shadows. (Default 0.065).";
> = 0.065;

uniform float Black_Anchor_Softness < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.08; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Black Floor Softness"; 
    ui_tooltip = "Controls the slope of the boost lead-in. (Default 0.04).";
> = 0.04;

uniform float Shadow_Protect < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.34; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Shadow Ramp Slope"; 
    ui_tooltip = "Shape of the boost in dark areas. (Default 1.17).";
> = 1.17;

uniform float Highlight_Protect < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 5.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Highlight Ramp Falloff"; 
    ui_tooltip = "Prevents over-boosting the sky and bright clouds. (Default 2.5).";
> = 2.5;

uniform bool Enable_Sky_Bias < 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Enable Sky ABL Bias"; 
    ui_tooltip = "Targeted Blue/Cyan protection specifically to prevent OLED ABL.";
> = true;

uniform float Sky_Bias < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 20.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Sky Bias Strength"; 
    ui_tooltip = "How hard to pinch the boost for blue sky hues. (Default 10.0).";
> = 10.0;

uniform bool Enable_Sat_Recover < 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Enable Saturation Recovery"; 
    ui_tooltip = "Restores color intensity in boosted areas to prevent perceptual washout.";
> = true;

uniform bool Enable_Adaptive_Sat < 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Use Adaptive Scaling"; 
    ui_tooltip = "Protects vibrant colors from 'clumping' during recovery.";
> = true;

uniform float Sat_Recover < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.20; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Saturation Recovery Amount"; 
    ui_tooltip = "Base strength of color restoration. (Default 0.10).";
> = 0.10;

uniform float Sat_Threshold < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 30.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Adaptive Sensitivity"; 
    ui_tooltip = "Aggressiveness of Color Volume protection. (Default 15.0).";
> = 15.0;

uniform bool Enable_Contrast_Recover < 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Enable Contrast Recovery"; 
    ui_tooltip = "Restores micro-texture specifically in boosted areas using signal-space contrast.";
> = true;

uniform float Contrast_Recover < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.50; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Contrast Strength"; 
    ui_tooltip = "Strength of high-frequency detail restoration. (Default 0.25).";
> = 0.25;

uniform bool Enable_Skin_Protect < 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Enable Skin Protection"; 
    ui_tooltip = "Masks human skin hues to prevent faces from over-brightening.";
> = true;

uniform float Skin_Protect_Strength < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Skin Protect Strength"; 
    ui_tooltip = "0.5 halves the boost on skin. 1.0 stops it entirely.";
> = 0.50;

uniform float Skin_Hue_Center < 
    ui_type = "slider"; ui_min = 1.36; ui_max = 3.14; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Skin Hue Center"; 
    ui_tooltip = "Target color for skin. (Default 2.25).";
> = 2.25;

uniform float Skin_Sensitivity < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.34; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Skin Mask Width"; 
    ui_tooltip = "Range of detected skin colors. (Default 0.17).";
> = 0.17;

uniform bool Debug_Skin < ui_category = "4. Debug Tools"; ui_label = "DEBUG: Show Skin Mask"; > = false;
uniform bool Debug_Heatmap < ui_category = "4. Debug Tools"; ui_label = "DEBUG: Show Boost Heatmap"; > = false;
uniform bool Show_Debug < ui_category = "4. Debug Tools"; ui_label = "Show Visual Stats"; > = false;

uniform int Help <
    ui_type = "radio"; ui_label = " "; ui_category = "99. Help & Mode Switching";
    ui_text = "HOW TO SWITCH MODES:\n1. Scroll to the bottom of the ReShade 'Home' tab.\n2. Find 'Preprocessor Definitions'.\n3. Set TRIGGER_MODE to 0 for Standard or 1 for ABL Curve.";
>;

// =============================================================================
// 3. STORAGE & SAMPLERS
// =============================================================================

texture texStats { Width = 32; Height = 32; Format = RGBA16F; };
sampler sStats { Texture = texStats; };
texture texSmooth { Width = 1; Height = 1; Format = RGBA16F; };
sampler sSmooth { Texture = texSmooth; };
texture texPrev { Width = 1; Height = 1; Format = RGBA16F; };
sampler sPrev { Texture = texPrev; };

sampler sLinear { Texture = ReShade::BackBufferTex; MinFilter = LINEAR; MagFilter = LINEAR; };

// =============================================================================
// 4. COLOR CONVERSION ENGINE
// =============================================================================

float3 Decode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 
    float3 cp = pow(max(c, 0.0), 0.012683);
    return pow(max((cp - 0.8359375) / (18.85156 - 18.6875 * cp), 0.0), 6.27739);
#elif BUFFER_COLOR_SPACE == 2 
    return c * 0.008; 
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
// 5. SHADER PASSES
// =============================================================================

float4 PS_CalcStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float3 c = tex2D(ReShade::BackBuffer, uv).rgb;
    float3 linearC = Decode(c);
    float rawSignalLuma = max(c.r, max(c.g, c.b));
    #if BUFFER_COLOR_SPACE == 2 
        rawSignalLuma = saturate(rawSignalLuma * 0.008); 
    #endif
    return float4(dot(linearC, LUMA_COEFF), rawSignalLuma, rawSignalLuma, 1);
}

float4 PS_SmoothStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float avg = 0, mx = 0, mn = 1.0;
    for(int i=0; i<32; i++) {
        for(int j=0; j<32; j++) {
            float3 s = tex2D(sStats, (float2(i, j) + 0.5) / 32.0).xyz;
            avg += s.x; mx = max(mx, s.y); mn = min(mn, s.z);
        }
    }
    float3 curr = float3(avg / 1024.0, mx, mn);
    float3 last = tex2D(sPrev, 0.5).xyz;
    return float4(lerp(curr, last, float3(Smoothing_Speed, Smoothing_Speed, 0.98)), 1);
}

float4 PS_LumaBoost(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    const float4 base = tex2D(ReShade::BackBuffer, uv);
    float4 LumaStats = tex2D(sSmooth, float2(0.5, 0.5));
    
    // --- TRIGGER LOGIC ---
    float trigger = 0.0;
    float activeBoost = 0.0;

#if TRIGGER_MODE == 1
    activeBoost = ABL_Boost;
    float apl_p = saturate((LumaStats.x * 10000.0) / max(P100, 1.0)) * 100.0;
    float cap = P001;
    if (apl_p <= 1.0) cap = P001;
    else if (apl_p <= 2.0) cap = lerp(P001, P002, saturate(apl_p - 1.0));
    else if (apl_p <= 5.0) cap = lerp(P002, P005, saturate((apl_p - 2.0) / 3.0));
    else if (apl_p <= 10.0) cap = lerp(P005, P010, saturate((apl_p - 5.0) / 5.0));
    else if (apl_p <= 25.0) cap = lerp(P010, P025, saturate((apl_p - 10.0) / 15.0));
    else if (apl_p <= 50.0) cap = lerp(P025, P050, saturate((apl_p - 25.0) / 25.0));
    else if (apl_p <= 75.0) cap = lerp(P050, P075, saturate((apl_p - 50.0) / 25.0));
    else cap = lerp(P075, P100, saturate((apl_p - 75.0) / 25.0));
    trigger = (max(P001 / max(cap, 1.0) - 1.0, 0.0));
#else
    activeBoost = Standard_Boost;
    float sigAPL = Encode(float3(LumaStats.x, 0.0, 0.0)).x;
    trigger = saturate((sigAPL - APL_Threshold) * Boost_Ramp);
#endif

    // --- COLOR PIPELINE ---
    float3 linearC = Decode(base.rgb);
    const float oldY = dot(linearC, LUMA_COEFF);
    const float linearPeak = Decode(float3(LumaStats.y, LumaStats.y, LumaStats.y)).x;
    const float anchorPeak = lerp(linearPeak, Decode(float3(LumaStats.x, LumaStats.x, LumaStats.x)).x, Specular_Immunity * 0.5);

    const float floorSig = Enable_Black_Anchor ? (LumaStats.z + Black_Anchor_Bias) : 0.0;
    const float linearFloor = Decode(float3(floorSig, floorSig, floorSig)).x;
    const float leadInSig = floorSig + Black_Anchor_Softness;
    const float linearLeadIn = Decode(float3(leadInSig, 0, 0)).x;
    const float floorTransition = smoothstep(linearFloor, max(linearLeadIn, linearFloor + 1e-7), oldY);

    float3 sigC = (BUFFER_COLOR_SPACE == 2) ? saturate(base.rgb * 0.008) : base.rgb;
    const float sigCb = dot(sigC, CHROMA_B);
    const float sigCr = dot(sigC, CHROMA_R);
    const float chroma = length(float2(sigCb, sigCr));
    const float hue = atan2(sigCr, sigCb);

    float3 outColor = linearC;
    float gainFactor = 0.0;

    if (oldY > linearFloor && oldY < linearPeak && trigger > 0.0) {
        float pX = pow(max(saturate((oldY - linearFloor) / max(anchorPeak - linearFloor, 1e-6)), 0.0), 0.45); 

        float skinMask = 0.0;
        [branch] if (Enable_Skin_Protect || Debug_Skin) {
            float d = abs(hue - Skin_Hue_Center); if (d > 3.14159) d = 6.28318 - d;
            skinMask = saturate(1.0 - d / max(Skin_Sensitivity, 0.01)) * saturate(chroma * 15.0);
        }

        float dynHighlightProt = Highlight_Protect;
        [branch] if (Enable_Sky_Bias) {
            float skyDist = abs(hue - (-0.5)); if (skyDist > 3.14159) skyDist = 6.28318 - skyDist;
            dynHighlightProt += (saturate(1.0 - skyDist / 0.4) * saturate(chroma * 10.0) * Sky_Bias);
        }

        float hump = pow(max(pX, 0.0), Shadow_Protect * 2.0) * pow(max(1.0 - pX, 0.0), dynHighlightProt * 2.0);
        float lift = trigger * activeBoost * hump * linearPeak * (1.0 - (skinMask * Skin_Protect_Strength * Enable_Skin_Protect));
        lift *= floorTransition; 
        
        gainFactor = lift / max(oldY, 1e-6); 
        float newY = oldY + lift;
        float3 boostedC = linearC * (newY / max(oldY, 1e-6));

        [branch] if (Enable_Sat_Recover) {
            float satInt = (lift / max(linearPeak, 1e-6)) * Sat_Recover * 10.0;
            if (Enable_Adaptive_Sat) satInt *= saturate(1.0 - chroma * Sat_Threshold * 0.1);
            outColor = lerp(float3(newY, newY, newY), boostedC, 1.0 + satInt);
        } else {
            outColor = boostedC;
        }

        if (Debug_Skin) outColor = lerp(outColor, float3(0.01, 0, 0.01), skinMask);
    }

    float3 finalSignal = Encode(outColor);

    [branch] if (Enable_Contrast_Recover && trigger > 0.0) {
        float2 off = ReShade::PixelSize * 0.5;
        float3 signalBlur = tex2D(sLinear, uv + off).rgb;
        finalSignal += (base.rgb - signalBlur) * Contrast_Recover * saturate(gainFactor * 5.0);
    }

    [branch] if (Debug_Heatmap) {
        float v = gainFactor / max(activeBoost, 1e-6);
        float3 heat = 0;
        heat = lerp(float3(0,0,0), float3(0,0,0.01), saturate(v * 5.0));
        heat = lerp(heat, float3(0,0.01,0.01), saturate(v * 5.0 - 1.0));
        heat = lerp(heat, float3(0,0.01,0), saturate(v * 5.0 - 2.0));
        heat = lerp(heat, float3(0.01,0.01,0), saturate(v * 5.0 - 3.0));
        heat = lerp(heat, float3(0.01,0,0), saturate(v * 5.0 - 4.0));
        finalSignal = Encode(heat);
    }

    [branch] if (Show_Debug) {
        float sigAPL = Encode(float3(LumaStats.x, 0.0, 0.0)).x;
        if (uv.y < 0.02) {
            if (uv.x < sigAPL) finalSignal = Encode(float3(0, 0.01, 0));
#if TRIGGER_MODE == 0
            if (abs(uv.x - APL_Threshold) < 0.001) finalSignal = Encode(float3(0.015, 0, 0));
#endif
        }
        if (uv.y > 0.022 && uv.y < 0.042) {
            float fV = Enable_Black_Anchor ? LumaStats.z : 0.0;
            if (uv.x < fV) finalSignal = Encode(float3(0.005, 0.005, 0.005));
            if (uv.x > fV && uv.x < LumaStats.y) finalSignal = Encode(float3(0, 0.002, 0.01));
        }
        if (uv.y > 0.044 && uv.y < 0.064) {
            if (uv.x < (trigger * activeBoost * 0.15)) finalSignal = Encode(float3(0.01, 0.005, 0));
        }
    }

    return float4(finalSignal, base.a);
}

float4 PS_SaveStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    return tex2D(sSmooth, float2(0.5, 0.5));
}

technique LumaBoost {
    pass { VertexShader = PostProcessVS; PixelShader = PS_CalcStats; RenderTarget = texStats; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SmoothStats; RenderTarget = texSmooth; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_LumaBoost; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SaveStats; RenderTarget = texPrev; }
}
