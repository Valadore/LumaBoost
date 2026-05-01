/*
================================================================================
    LumaBoost - Professional EOTF & Brightness Compensation (v1.5 Master)
================================================================================
    
    DEVELOPMENT LOGIC:
    LumaBoost emulates premium display hardware logic. On OLED panels, bright 
    scenes trigger an internal Auto Brightness Limiter (ABL) that dims the 
    entire screen to protect the panel. This shader fights that dimming by 
    dynamically lifting midtones while using advanced "Protection Masks" 
    to ensure that skin tones, deep blacks, and the bright sky are not 
    distorted or over-processed.

    ENGINEERING HIGHLIGHTS:
    - Format-Aware: Internal math scales automatically for SDR, HDR10, and scRGB.
    - Constant Hue: Uses RGB-Ratio scaling so colors never shift (e.g. Red to Orange).
    - Temporal Logic: Transitions happen over several frames to prevent flickering.
    - Perception-Based: Math is done in Linear Light but weighted perceptually.
================================================================================
*/

#include "ReShade.fxh"

// =============================================================================
// 1. SYSTEM DETECTION & CONSTANTS
// =============================================================================

#if BUFFER_COLOR_SPACE == 3 // HDR10 PQ (Uses BT.2020 Primaries)
    #define CS_NAME "HDR10 (PQ)"
    #define LUMA_COEFF float3(0.2627, 0.6780, 0.0593) // Standards for Wide Gamut
    #define CHROMA_B   float3(-0.1396, -0.3604, 0.5)
    #define CHROMA_R   float3(0.5, -0.4598, -0.0402)
#elif BUFFER_COLOR_SPACE == 2 // scRGB Linear (Uses BT.709 Primaries)
    #define CS_NAME "scRGB (Linear)"
    #define LUMA_COEFF float3(0.2126, 0.7152, 0.0722) // Standard Gamut weights
    #define CHROMA_B   float3(-0.1146, -0.3854, 0.5)
    #define CHROMA_R   float3(0.5, -0.4542, -0.0458)
#else // SDR sRGB (Uses BT.709 Primaries)
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
    ui_text = "Detected Format: " CS_NAME;
    ui_tooltip = "This shows the color space ReShade has detected for the current game.\nLumaBoost automatically adjusts its coefficients for Luma (brightness) and Chroma (color) to match this format.";
>;

uniform float APL_Threshold <
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.40;
    ui_category = "1. Main Boost Settings";
    ui_label = "APL Trigger Threshold";
    ui_tooltip = "Defines how bright the whole screen needs to be before the boost starts working.\n0.20 (Default) is tuned for standard gameplay. Lower values make the boost kick in during darker scenes.";
> = 0.20;

uniform float Boost <
    ui_type = "slider"; ui_min = 0.0; ui_max = 6.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Max Boost Strength";
    ui_tooltip = "The maximum intensity of the brightness lift.\nIncreasing this makes midtones punchier but may look artificial if set too high.";
> = 3.0;

uniform float Boost_Ramp <
    ui_type = "slider"; ui_min = 0.0; ui_max = 8.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Boost Activation Sensitivity";
    ui_tooltip = "Controls how fast the boost reaches full power once the threshold is crossed.\nLower values create a subtle build-up; higher values make the boost snap in instantly.";
> = 4.0;

uniform float Smoothing_Speed <
    ui_type = "slider"; ui_min = 0.9; ui_max = 1.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Temporal Smoothing";
    ui_tooltip = "Glides brightness changes over time to prevent 'pulsing' or flickering when lights move.\n0.95 (Default) provides a smooth, monitor-like transition.";
> = 0.95;

uniform bool Enable_Black_Anchor <
    ui_category = "1. Main Boost Settings";
    ui_label = "Enable Dynamic Black Anchor";
    ui_tooltip = "Detects the dimmest pixel in every frame to anchor the boost start point.\nThis ensures 'inky blacks' remain 100% untouched regardless of how much boost is applied.";
> = true;

uniform float Black_Anchor_Bias <
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.12;
    ui_category = "1. Main Boost Settings";
    ui_label = "Black Floor Offset";
    ui_tooltip = "Pushes the 'Zero Boost' zone deeper into the shadows.\nIncrease this if the boost is making dark grey areas feel too bright or washed out.";
> = 0.06;

uniform float Black_Anchor_Softness <
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.06;
    ui_category = "1. Main Boost Settings";
    ui_label = "Black Floor Softness";
    ui_tooltip = "Controls the 'slope' of the boost lead-in.\nHigher values create a more gradual fade-in from the black shadows into the boosted midtones.";
> = 0.03;

uniform float Shadow_Protect <
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Shadow Ramp Slope";
    ui_tooltip = "Changes the shape of the boost curve in the dark areas.\n1.0 is balanced. Higher values hollow out the shadows, keeping them darker for longer.";
> = 1.0;

uniform float Highlight_Protect <
    ui_type = "slider"; ui_min = 0.0; ui_max = 4.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Highlight Ramp Falloff";
    ui_tooltip = "Controls how aggressively the boost dies off as it reaches highlights.\nIncrease this to stop the sky and bright clouds from being over-boosted.";
> = 2.0;

uniform float Specular_Immunity <
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Specular Immunity";
    ui_tooltip = "Prevents a tiny bright highlight (like the sun or a lamp) from 'tricking' the shader into dimming the rest of the world.\n0.5 (Default) allows for a balanced response.";
> = 0.5;

uniform bool Enable_Sky_Bias < 
    ui_category = "1. Main Boost Settings"; 
    ui_label = "Enable Sky ABL Bias"; 
    ui_tooltip = "Targeted protection for Blue/Cyan hues.\nAutomatically applies extra protection to the sky to prevent it from triggering the monitor's internal dimming.";
> = true;

uniform float Sky_Bias < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 10.0; 
    ui_category = "1. Main Boost Settings"; 
    ui_label = "Sky Bias Strength"; 
    ui_tooltip = "How much extra protection to apply to blue hues specifically.";
> = 5.0;

uniform bool Enable_Sat_Recover < 
    ui_category = "2. Color Correction"; 
    ui_label = "Enable Saturation Recovery"; 
    ui_tooltip = "Fights the 'Hunt Effect' (perceptual washout).\nRestores color intensity in boosted areas so they don't look greyish or foggy.";
> = true;

uniform bool Enable_Adaptive_Sat < 
    ui_category = "2. Color Correction"; 
    ui_label = "Use Adaptive Scaling"; 
    ui_tooltip = "Automatically reduces saturation recovery for pixels that are already very colorful.\nThis prevents bright red or blue objects from 'glowing' or losing texture.";
> = true;

uniform float Sat_Recover < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.20; 
    ui_category = "2. Color Correction"; 
    ui_label = "Saturation Recovery Amount"; 
    ui_tooltip = "Base strength of color restoration. Default: 0.10.";
> = 0.10;

uniform float Sat_Threshold < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 30.0; 
    ui_category = "2. Color Correction"; 
    ui_label = "Adaptive Sat. Sensitivity"; 
    ui_tooltip = "How aggressively to protect saturated colors. Higher values prevent color clipping more strictly.";
> = 15.0;

uniform bool Enable_Contrast_Recover < 
    ui_category = "2. Color Correction"; 
    ui_label = "Enable Contrast Recovery"; 
    ui_tooltip = "Boosted pixels are often 'stretched', making them look soft.\nThis restores local micro-contrast specifically to the boosted areas for a tangible look.";
> = true;

uniform float Contrast_Recover < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.50; 
    ui_category = "2. Color Correction"; 
    ui_label = "Contrast Strength"; 
    ui_tooltip = "Strength of the high-frequency detail restoration.";
> = 0.25;

uniform bool Enable_Skin_Protect < 
    ui_category = "3. Skin Protection"; 
    ui_label = "Enable Skin Protection"; 
    ui_tooltip = "Uses an intelligent mask to detect human skin hues and reduce the boost on character faces.";
> = true;

uniform float Skin_Protect_Strength < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; 
    ui_category = "3. Skin Protection"; 
    ui_label = "Protection Strength"; 
    ui_tooltip = "0.5 (Default) halves the boost on skin. 1.0 stops the boost entirely on faces.";
> = 0.50;

uniform float Skin_Hue_Center < 
    ui_type = "slider"; ui_min = 1.36; ui_max = 3.14; 
    ui_category = "3. Skin Protection"; 
    ui_label = "Hue Center"; 
    ui_tooltip = "The 'Target Color' for skin. Use the DEBUG tool to ensure character faces turn purple.";
> = 2.25;

uniform float Skin_Sensitivity < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 0.34; 
    ui_category = "3. Skin Protection"; 
    ui_label = "Mask Width"; 
    ui_tooltip = "How broad the skin detection is. (Default 0.17).";
> = 0.17;

uniform bool Debug_Skin < 
    ui_category = "4. Debug Tools"; 
    ui_label = "DEBUG: Show Skin Mask"; 
    ui_tooltip = "Turns all skin purple. Essential for calibrating 'Hue Center'.";
> = false;

uniform bool Debug_Heatmap < 
    ui_category = "4. Debug Tools"; 
    ui_label = "DEBUG: Show Boost Heatmap"; 
    ui_tooltip = "Visualizes exactly where boost is being applied.\nRED: Max Boost. BLACK: Protected areas (Shadows/Skin/Sky).";
> = false;

uniform bool Show_Debug < 
    ui_category = "4. Debug Tools"; 
    ui_label = "Show Visual Stats"; 
    ui_tooltip = "TOP BAR: Current Brightness (Green) vs Threshold (Red).\nMIDDLE BAR: Current Frame Floor to Peak (Blue).\nBOTTOM BAR: Active Boost Intensity (Orange).";
> = false;

// =============================================================================
// 3. STORAGE & SAMPLERS
// =============================================================================

texture texStats { Width = 32; Height = 32; Format = RGBA16F; };
sampler sStats { Texture = texStats; };
texture texSmooth { Width = 1; Height = 1; Format = RGBA16F; };
sampler sSmooth { Texture = texSmooth; };
texture texPrev { Width = 1; Height = 1; Format = RGBA16F; };
sampler sPrev { Texture = texPrev; };

// Linear sampler using ReShade::BackBufferTex for DX12 stability
sampler sLinear { Texture = ReShade::BackBufferTex; MinFilter = LINEAR; MagFilter = LINEAR; };

// =============================================================================
// 4. COLOR CONVERSION ENGINE
// =============================================================================

// Decodes standard signals into a unified 'Linear Nits' space
float3 Decode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 // PQ Decode (Standard for HDR10)
    float3 cp = pow(max(c, 0.0), 0.012683);
    return pow(max((cp - 0.8359375) / (18.85156 - 18.6875 * cp), 0.0), 6.27739);
#elif BUFFER_COLOR_SPACE == 2 // scRGB (Windows Linear HDR)
    return c * 0.008; // Maps 125.0 to 1.0 (10k nits)
#else // SDR (Standard sRGB/Gamma 2.2)
    return pow(max(c, 0.0), 2.2);
#endif
}

// Encodes Linear Light back into the game's expected format
float3 Encode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 // PQ Encode
    float3 cp = pow(max(c, 0.0), 0.159301);
    return pow(max((0.8359375 + 18.85156 * cp) / (1.0 + 18.6875 * cp), 0.0), 78.84375);
#elif BUFFER_COLOR_SPACE == 2 // scRGB Encode
    return c * 125.0; 
#else // SDR Encode
    return pow(max(c, 0.0), 0.454545);
#endif
}

// =============================================================================
// 5. SHADER PASSES
// =============================================================================

// Pass 1: Capture the frame into a 32x32 grid to analyze brightness levels
float4 PS_CalcStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float3 c = tex2D(ReShade::BackBuffer, uv).rgb;
    #if BUFFER_COLOR_SPACE == 2 
        c = saturate(c * 0.008); // Normalize scRGB for analysis
    #endif
    return float4(max(c.r, max(c.g, c.b)), 0, 0, 1);
}

// Pass 2: Calculate frame stats (Average/Peak/Floor) and apply Temporal Smoothing
float4 PS_SmoothStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float avg = 0, mx = 0, mn = 1.0;
    
    // Scan the analyzed grid
    for(int i=0; i<32; i++) {
        for(int j=0; j<32; j++) {
            float s = tex2D(sStats, (float2(i, j) + 0.5) / 32.0).x;
            avg += s; mx = max(mx, s); mn = min(mn, s);
        }
    }
    
    float3 curr = float3(avg / 1024.0, mx, mn);
    float3 last = tex2D(sPrev, 0.5).xyz;
    // Blend current values with previous frames for cinematic stability
    return float4(lerp(curr, last, float3(Smoothing_Speed, Smoothing_Speed, 0.98)), 1);
}

// Pass 3: The Main Luma Boost Logic
float4 PS_LumaBoost(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    const float4 base = tex2D(ReShade::BackBuffer, uv);
    const float3 stats = tex2D(sSmooth, 0.5).xyz;
    const float trigger = saturate((stats.x - APL_Threshold) * Boost_Ramp);

    // Decode signal to Linear Light for mathematically correct math
    float3 linearC = Decode(base.rgb);
    const float oldY = dot(linearC, LUMA_COEFF);
    const float linearPeak = Decode(float3(stats.y, stats.y, stats.y)).r;
    
    // Anchor logic: Interpolates peak based on Specular Immunity
    const float anchorPeak = lerp(linearPeak, Decode(float3(stats.x, stats.x, stats.x)).r, Specular_Immunity * 0.5);

    // Dynamic Floor calculation
    const float floorSig = Enable_Black_Anchor ? (stats.z + Black_Anchor_Bias) : 0.0;
    const float linearFloor = Decode(float3(floorSig, floorSig, floorSig)).r;
    
    // Calculate the lead-in slope for the black floor
    const float leadInSig = floorSig + Black_Anchor_Softness;
    const float linearLeadIn = Decode(float3(leadInSig, leadInSig, leadInSig)).r;
    const float floorTransition = smoothstep(linearFloor, max(linearLeadIn, linearFloor + 1e-7), oldY);

    // Generate chroma-accurate signal space for Skin Detection
    float3 signalC = (BUFFER_COLOR_SPACE == 2) ? saturate(base.rgb * 0.008) : base.rgb;
    const float sigCb = dot(signalC, CHROMA_B);
    const float sigCr = dot(signalC, CHROMA_R);
    const float chroma = length(float2(sigCb, sigCr));
    const float hue = atan2(sigCr, sigCb);

    float3 outColor = linearC;
    float gainFactor = 0.0;

    // Apply Boost only if pixel is in range and boost is triggered
    if (oldY > linearFloor && oldY < linearPeak && trigger > 0.0) {
        // Map linear light back to Perceptual scale (Gamma 2.2 approx) for hump targeting
        float pX = pow(max(saturate((oldY - linearFloor) / max(anchorPeak - linearFloor, 1e-6)), 0.0), 0.45); 

        // Skin Mask detection
        float skinMask = 0.0;
        [branch] if (Enable_Skin_Protect || Debug_Skin) {
            float d = abs(hue - Skin_Hue_Center); if (d > 3.14159) d = 6.28318 - d;
            skinMask = saturate(1.0 - d / max(Skin_Sensitivity, 0.01)) * saturate(chroma * 15.0);
        }

        // Sky Bias detection (Targeting Blue ~ -0.5 radians)
        float dynHighlightProt = Highlight_Protect;
        [branch] if (Enable_Sky_Bias) {
            float skyDist = abs(hue - (-0.5)); if (skyDist > 3.14159) skyDist = 6.28318 - skyDist;
            dynHighlightProt += (saturate(1.0 - skyDist / 0.4) * saturate(chroma * 10.0) * Sky_Bias);
        }

        // Calculate the Gain 'Hump'
        float hump = pow(max(pX, 0.0), Shadow_Protect * 2.0) * pow(max(1.0 - pX, 0.0), dynHighlightProt * 2.0);
        float lift = Boost * trigger * hump * linearPeak * (1.0 - (skinMask * Skin_Protect_Strength * Enable_Skin_Protect));
        lift *= floorTransition; // Smooth lead-in from black anchor
        
        gainFactor = lift / max(oldY, 1e-6); 
        float newY = oldY + lift;
        // Apply brightness lift using hue-stable RGB ratio scaling
        float3 boostedC = linearC * (newY / max(oldY, 1e-6));

        // Apply Perceptual Saturation Recovery
        [branch] if (Enable_Sat_Recover) {
            float satInt = (lift / max(linearPeak, 1e-6)) * Sat_Recover * 10.0;
            // Adaptive scaling prevents color volume clipping
            if (Enable_Adaptive_Sat) satInt *= saturate(1.0 - chroma * Sat_Threshold * 0.1);
            outColor = lerp(float3(newY, newY, newY), boostedC, 1.0 + satInt);
        } else {
            outColor = boostedC;
        }

        // Apply skin purple overlay if debugging
        if (Debug_Skin) outColor = lerp(outColor, float3(0.01, 0, 0.01), skinMask);
    }

    // Re-encode to the original backbuffer signal space
    float3 finalSignal = Encode(outColor);

    // Apply Contrast Recovery in Signal Space to prevent shadow noise
    [branch] if (Enable_Contrast_Recover && trigger > 0.0) {
        float2 off = ReShade::PixelSize * 0.5;
        // Hardware bilinear tap for optimized averaging
        float3 signalBlur = tex2D(sLinear, uv + off).rgb;
        finalSignal += (base.rgb - signalBlur) * Contrast_Recover * saturate(gainFactor * 5.0);
    }

    // False-color Heatmap Overlay
    [branch] if (Debug_Heatmap) {
        float v = gainFactor / max(Boost, 1e-6);
        float3 heat = 0;
        heat = lerp(float3(0,0,0),       float3(0,0,0.01),    saturate(v * 5.0));
        heat = lerp(heat,                float3(0,0.01,0.01), saturate(v * 5.0 - 1.0));
        heat = lerp(heat,                float3(0,0.01,0),    saturate(v * 5.0 - 2.0));
        heat = lerp(heat,                float3(0.01,0.01,0), saturate(v * 5.0 - 3.0));
        heat = lerp(heat,                float3(0.01,0,0),    saturate(v * 5.0 - 4.0));
        finalSignal = Encode(heat);
    }

    // Visual Stats Bar Rendering
    [branch] if (Show_Debug) {
        if (uv.y < 0.02) {
            if (uv.x < stats.x) finalSignal = Encode(float3(0, 0.01, 0));
            if (abs(uv.x - APL_Threshold) < 0.001) finalSignal = Encode(float3(0.015, 0, 0));
        }
        if (uv.y > 0.022 && uv.y < 0.042) {
            float fV = Enable_Black_Anchor ? stats.z : 0.0;
            if (uv.x < fV) finalSignal = Encode(float3(0.005, 0.005, 0.005));
            if (uv.x > fV && uv.x < stats.y) finalSignal = Encode(float3(0, 0.002, 0.01));
        }
        if (uv.y > 0.044 && uv.y < 0.064) {
            if (uv.x < (trigger * Boost * 0.15)) finalSignal = Encode(float3(0.01, 0.005, 0));
        }
    }

    return float4(finalSignal, base.a);
}

// Pass 4: Save current stats for next frame's temporal lerp
float4 PS_SaveStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    return tex2D(sSmooth, 0.5);
}

// =============================================================================
// 6. TECHNIQUE DEFINITION
// =============================================================================

technique LumaBoost {
    pass { VertexShader = PostProcessVS; PixelShader = PS_CalcStats; RenderTarget = texStats; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SmoothStats; RenderTarget = texSmooth; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_LumaBoost; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SaveStats; RenderTarget = texPrev; }
}
