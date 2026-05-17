/*
================================================================================
    LumaBoost - Master Edition v6
================================================================================
    
    PURPOSE:
    A high-fidelity display-hardware emulator designed to counteract OLED ABL.
    It dynamically lifts midtones when the screen dims, preserving the intended
    High Dynamic Range (HDR) experience.

    CALIBRATION LOGIC:
    - Nit-Aware: Internal detection standardized to physical light (nits).
    - Centered UI: Slider ranges calculated to place defaults at midpoints.
    - DX12 Verified: Strict type-safety for maximum stability in Witcher 3.

    MODE SWITCHING (Bottom of Home Tab):
    0 : Standard Mode | 1 : ABL Curve Mode
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
// 2. UI CONTROLS (Defaults precisely centered)
// =============================================================================

uniform int Info <
    ui_type = "radio"; ui_label = " "; ui_category = "0. System Info";
    ui_text = "Format: " CS_NAME "\nMode: " MODE_STR;
>;

// --- MODE 0: STANDARD ---
#if TRIGGER_MODE == 0
uniform bool Enable_Standard_Settings < ui_category = "1. Standard Mode Settings"; ui_label = "EXPAND SETTINGS"; ui_category_toggle = true; > = true;
uniform float Standard_Boost <
    ui_type = "slider"; ui_min = 0.0; ui_max = 6.0;
    ui_category = "1. Standard Mode Settings";
    ui_label = "Standard: Boost Strength";
> = 3.0;

uniform float APL_Threshold <
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.44;
    ui_category = "1. Standard Mode Settings";
    ui_label = "Standard: APL Threshold";
> = 0.22;

uniform float Boost_Ramp <
    ui_type = "slider"; ui_min = 0.0; ui_max = 7.948;
    ui_category = "1. Standard Mode Settings";
    ui_label = "Standard: Sensitivity";
> = 3.974;
#endif

// --- MODE 1: ABL CURVE ---
#if TRIGGER_MODE == 1
uniform bool Enable_ABL_Settings < ui_category = "1. ABL Mode Settings"; ui_label = "EXPAND SETTINGS"; ui_category_toggle = true; > = true;
uniform float ABL_Boost <
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0;
    ui_category = "1. ABL Mode Settings";
    ui_label = "Compensation Strength";
    ui_tooltip = "1.0 tries to perfectly counteract panel dimming. (Centered).";
> = 1.0;

uniform float Target_Nits <
    ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0;
    ui_category = "1. ABL Mode Settings";
    ui_label = "Calibration: Master Target";
> = 1000.0;

uniform bool Show_Data_Points <
    ui_category = "2. Monitor ABL Data Points";
    ui_label = "EDIT CALIBRATION DATA";
    ui_category_toggle = true;
> = false;

uniform float P001 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = "1% Window capability"; > = 994.0;
uniform float P002 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = "2% Window capability"; > = 943.0;
uniform float P005 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = "5% Window capability"; > = 718.0;
uniform float P010 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = "10% Window capability"; > = 451.0;
uniform float P025 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = "25% Window capability"; > = 361.0;
uniform float P050 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = "50% Window capability"; > = 303.0;
uniform float P075 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = "75% Window capability"; > = 273.0;
uniform float P100 < ui_type = "drag"; ui_min = 100.0; ui_max = 2000.0; ui_category = "2. Monitor ABL Data Points"; ui_label = "100% Window capability"; > = 258.0;
#endif

// --- ADVANCED QUALITY & PROTECTION ---

uniform bool Enable_Advanced < ui_category = "3. Advanced Quality & Protection"; ui_label = "SHOW ADVANCED SETTINGS"; ui_category_toggle = true; > = true;

uniform float Smoothing_Speed < 
    ui_type = "slider"; ui_min = 0.96; ui_max = 1.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Temporal Smoothing"; 
> = 0.98;

uniform float Specular_Immunity < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Specular Immunity"; 
> = 0.50;

uniform bool Enable_Black_Anchor < ui_category = "3. Advanced Quality & Protection"; ui_label = "Enable Black Floor Tracking"; > = true;

uniform float Black_Floor_Offset_Nits < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.30; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Black Floor Offset (Nits)"; 
    ui_tooltip = "Physical light level where boost starts. (Default: 0.15).";
> = 0.15;

uniform float Black_Floor_Softness_Nits < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 14.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Black Floor Softness (Nits)"; 
    ui_tooltip = "Radius of the lead-in slope. (Default: 7.0).";
> = 7.0;

uniform float Shadow_Protect < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Shadow Ramp Slope"; 
> = 1.0;

uniform float Highlight_Protect < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 5.0; 
    ui_category = "3. Advanced Quality & Protection"; 
    ui_label = "Highlight Ramp Falloff"; 
> = 2.5;

uniform bool Enable_Sky_Bias < ui_category = "3. Advanced Quality & Protection"; ui_label = "Enable Sky ABL Bias"; > = true;
uniform float Sky_Bias < ui_type = "slider"; ui_min = 0.0; ui_max = 20.0; ui_category = "3. Advanced Quality & Protection"; ui_label = "Sky Bias Strength"; > = 10.0;

uniform bool Enable_Sat_Recover < ui_category = "3. Advanced Quality & Protection"; ui_label = "Enable Saturation Recovery"; > = true;
uniform bool Enable_Adaptive_Sat < ui_category = "3. Advanced Quality & Protection"; ui_label = "Use Adaptive Scaling"; > = true;
uniform float Sat_Recover < ui_type = "slider"; ui_min = 0.0; ui_max = 0.51; ui_category = "3. Advanced Quality & Protection"; ui_label = "Sat Recovery Amount"; > = 0.255;
uniform float Sat_Threshold < ui_type = "slider"; ui_min = 0.0; ui_max = 30.0; ui_category = "3. Advanced Quality & Protection"; ui_label = "Adaptive Sensitivity"; > = 15.0;

uniform bool Enable_Contrast_Recover < ui_category = "3. Advanced Quality & Protection"; ui_label = "Enable Contrast Recovery"; > = true;
uniform float Contrast_Recover < ui_type = "slider"; ui_min = 0.0; ui_max = 0.40; ui_category = "3. Advanced Quality & Protection"; ui_label = "Contrast Strength"; > = 0.20;

uniform bool Enable_Skin_Protect < ui_category = "3. Advanced Quality & Protection"; ui_label = "Enable Skin Protection"; > = false;
uniform float Skin_Protect_Strength < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "3. Advanced Quality & Protection"; ui_label = "Skin Protect Strength"; > = 0.50;
uniform float Skin_Hue_Center < ui_type = "slider"; ui_min = 1.36; ui_max = 3.14; ui_category = "3. Advanced Quality & Protection"; ui_label = "Skin Hue Center"; > = 2.253;
uniform float Skin_Sensitivity < ui_type = "slider"; ui_min = 0.0; ui_max = 0.34; ui_category = "3. Advanced Quality & Protection"; ui_label = "Skin Mask Width"; > = 0.17;

uniform bool Debug_Skin < ui_category = "4. Debug Tools"; ui_label = "DEBUG: Show Skin Mask"; > = false;
uniform bool Debug_Heatmap < ui_category = "4. Debug Tools"; ui_label = "DEBUG: Show Boost Heatmap"; > = false;
uniform bool Show_Debug < ui_category = "4. Debug Tools"; ui_label = "Show Visual Stats"; > = false;

uniform int Help <
    ui_type = "radio"; ui_label = " "; ui_category = "99. Help & Mode Switching";
    ui_text = "HOW TO SWITCH MODES:\n1. Scroll to the bottom of the ReShade 'Home' tab.\n2. Find 'Preprocessor Definitions'.\n3. Set TRIGGER_MODE to 0 for Standard or 1 for ABL.";
>;

// =============================================================================
// 3. STORAGE
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
#if BUFFER_COLOR_SPACE == 3 // PQ -> Absolute Nits
    float3 cp = pow(max(c, 0.0), 0.012683);
    return pow(max((cp - 0.8359375) / (18.85156 - 18.6875 * cp), 0.0), 6.27739) * 10000.0;
#elif BUFFER_COLOR_SPACE == 2 // scRGB -> Nits (1.0 = 80)
    return c * 80.0; 
#else // SDR -> Nits (1.0 = 203)
    return pow(max(c, 0.0), 2.2) * 203.0;
#endif
}

float3 Encode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 // Nits -> PQ
    float3 cp = pow(max(c / 10000.0, 0.0), 0.159301);
    return pow(max((0.8359375 + 18.85156 * cp) / (1.0 + 18.6875 * cp), 0.0), 78.84375);
#elif BUFFER_COLOR_SPACE == 2 // Nits -> scRGB
    return c / 80.0; 
#else // Nits -> SDR
    return pow(max(c / 203.0, 0.0), 0.454545);
#endif
}

// =============================================================================
// 5. SHADER PASSES
// =============================================================================

float4 PS_CalcStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float3 c = tex2D(ReShade::BackBuffer, uv).rgb;
    float3 linearC = Decode(c);
    float luma = dot(linearC, LUMA_COEFF);
    float nitNorm = luma / 10000.0;
    return float4(luma, nitNorm, nitNorm, 1);
}

float4 PS_SmoothStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float avgNits = 0, mxNits = 0, mnNits = 1.0;
    for(int i=0; i<32; i++) {
        for(int j=0; j<32; j++) {
            float3 s = tex2D(sStats, (float2(i, j) + 0.5) / 32.0).xyz;
            avgNits += s.x; mxNits = max(mxNits, s.y); mnNits = min(mnNits, s.z);
        }
    }
    float3 curr = float3(avgNits / 1024.0, mxNits, mnNits);
    float3 last = tex2D(sPrev, 0.5).xyz;
    return float4(lerp(curr, last, Smoothing_Speed), 1);
}

float4 PS_LumaBoost(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    const float4 base = tex2D(ReShade::BackBuffer, uv);
    const float3 LumaStats = (float3)tex2D(sSmooth, float2(0.5, 0.5)).xyz;
    
    float trigger = 0.0;
    float activeBoost = 0.0;

#if TRIGGER_MODE == 1
    activeBoost = ABL_Boost;
    float apl_p = saturate(LumaStats.x / max(P100, 1.0)) * 100.0;
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

    float3 linearC = Decode(base.rgb);
    const float oldY = dot(linearC, LUMA_COEFF);
    const float linearPeak = LumaStats.y * 10000.0;
    const float anchorPeak = lerp(linearPeak, LumaStats.x, Specular_Immunity * 0.5);

    const float floorNits = Enable_Black_Anchor ? (LumaStats.z * 10000.0 + Black_Floor_Offset_Nits) : 0.0;
    const float leadInNits = floorNits + Black_Floor_Softness_Nits;
    const float floorTransition = smoothstep(floorNits, max(leadInNits, floorNits + 1e-7), oldY);

    float3 sigC = (BUFFER_COLOR_SPACE == 2) ? saturate(base.rgb * 0.008) : base.rgb;
    const float sigCb = dot(sigC, CHROMA_B);
    const float sigCr = dot(sigC, CHROMA_R);
    const float chroma = length(float2(sigCb, sigCr));
    const float hue = atan2(sigCr, sigCb);

    float3 outColor = linearC;
    float gainFactor = 0.0;

    if (oldY > floorNits && oldY < linearPeak && trigger > 0.0) {
        float pX = pow(max(saturate((oldY - floorNits) / max(anchorPeak - floorNits, 1e-6)), 0.0), 0.45); 

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
        if (Debug_Skin) outColor = lerp(outColor, float3(100.0, 0, 100.0), skinMask);
    }

    float3 finalSignal = Encode(outColor);

    [branch] if (Enable_Contrast_Recover && trigger > 0.0) {
        float2 off = ReShade::PixelSize * 0.5;
        float3 signalBlur = tex2D(sLinear, uv + off).rgb;
        finalSignal += (base.rgb - signalBlur) * Contrast_Recover * saturate(gainFactor * 5.0);
    }

    [branch] if (Debug_Heatmap) {
        float v = gainFactor / max(3.0, 1e-6);
        float3 heat = lerp(float3(0,0,0), float3(0,50,150), saturate(v * 5.0));
        heat = lerp(heat, float3(0,150,0), saturate(v * 5.0 - 2.0));
        heat = lerp(heat, float3(150,0,0), saturate(v * 5.0 - 4.0));
        finalSignal = Encode(heat);
    }

    if (Show_Debug) {
        float sigAPL = Encode(float3(LumaStats.x, 0.0, 0.0)).x;
        if (uv.y < 0.02) {
            if (uv.x < sigAPL) finalSignal = Encode(float3(0, 100, 0));
#if TRIGGER_MODE == 0
            if (abs(uv.x - APL_Threshold) < 0.001) finalSignal = Encode(float3(150, 0, 0));
#endif
        }
        if (uv.y > 0.022 && uv.y < 0.042) {
            float fV = Enable_Black_Anchor ? LumaStats.z : 0.0;
            if (uv.x < fV) finalSignal = Encode(float3(50, 50, 50));
            if (uv.x > fV && uv.x < LumaStats.y) finalSignal = Encode(float3(0, 20, 100));
        }
        if (uv.y > 0.044 && uv.y < 0.064) {
            if (uv.x < (trigger * 0.15)) finalSignal = Encode(float3(100, 50, 0));
        }
    }

    return float4(finalSignal, base.a);
}

float4 PS_SaveStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    return tex2D(sSmooth, 0.5);
}

technique LumaBoost {
    pass { VertexShader = PostProcessVS; PixelShader = PS_CalcStats; RenderTarget = texStats; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SmoothStats; RenderTarget = texSmooth; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_LumaBoost; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SaveStats; RenderTarget = texPrev; }
}
