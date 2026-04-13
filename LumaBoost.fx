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
// SYSTEM INFO
// =============================================================================

#if BUFFER_COLOR_SPACE == 3
    #define CS_NAME "HDR10 (PQ)"
#elif BUFFER_COLOR_SPACE == 2
    #define CS_NAME "scRGB (Linear)"
#else
    #define CS_NAME "SDR (sRGB)"
#endif

// =============================================================================
// UI CONTROLS
// =============================================================================

uniform int Info <
    ui_type = "radio"; ui_label = " "; ui_category = "0. System Info";
    ui_text = "Detected Buffer Format: " CS_NAME;
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
> = 0.5;

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
    ui_type = "slider"; ui_min = 1.0; ui_max = 10.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Shadow Protect";
> = 1.0;

uniform bool Enable_Sat_Recover < ui_category = "2. Color Correction"; ui_label = "Enable Saturation Recovery"; > = true;
uniform float Sat_Recover < 
    ui_type = "slider"; ui_min = 0.0; ui_max = 2.0; 
    ui_category = "2. Color Correction"; ui_label = "Saturation Recovery Amount"; 
    ui_tooltip = "Fights 'washout'. Higher values make colors more vivid as brightness increases.";
> = 0.15;

uniform bool Enable_Skin_Protect < ui_category = "3. Skin Protection"; ui_label = "Enable Skin Protection"; > = true;
uniform float Skin_Protect_Strength < ui_type = "slider"; ui_min = 0.0; ui_max = 1.0; ui_category = "3. Skin Protection"; ui_label = "Protection Strength"; > = 0.50;
uniform float Skin_Hue_Center < ui_type = "slider"; ui_min = 0.0; ui_max = 3.14; ui_category = "3. Skin Protection"; ui_label = "Hue Center"; > = 2.25;
uniform float Skin_Sensitivity < ui_type = "slider"; ui_min = 0.05; ui_max = 1.0; ui_category = "3. Skin Protection"; ui_label = "Mask Width"; > = 0.25;

uniform bool Debug_Skin < ui_category = "4. Debug Tools"; ui_label = "DEBUG: Show Skin Mask"; > = false;
uniform bool Show_Debug < ui_category = "4. Debug Tools"; ui_label = "Show Visual Stats"; > = false;

// =============================================================================
// COLOR SCIENCE
// =============================================================================

float3 Decode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 
    const float m1 = 0.1593017578125, m2 = 78.84375, c1 = 0.8359375, c2 = 18.8515625, c3 = 18.6875;
    float3 cp = pow(max(c, 0.0), 1.0 / m2);
    return pow(max(cp - c1, 0.0) / (c2 - c3 * cp), 1.0 / m1);
#elif BUFFER_COLOR_SPACE == 2 
    return c / 125.0; 
#else 
    return pow(max(c, 0.0), 2.2);
#endif
}

float3 Encode(float3 c) {
#if BUFFER_COLOR_SPACE == 3 
    const float m1 = 0.1593017578125, m2 = 78.84375, c1 = 0.8359375, c2 = 18.8515625, c3 = 18.6875;
    float3 cp = pow(max(c, 0.0), m1);
    return pow((c1 + c2 * cp) / (1.0 + c3 * cp), m2);
#elif BUFFER_COLOR_SPACE == 2 
    return c * 125.0;
#else 
    return pow(max(c, 0.0), 1.0 / 2.2);
#endif
}

// =============================================================================
// STATS HANDLING
// =============================================================================

texture texStats { Width = 32; Height = 32; Format = RGBA16F; };
sampler samplerStats { Texture = texStats; };
texture texStatsPrev { Width = 1; Height = 1; Format = RGBA16F; };
sampler samplerStatsPrev { Texture = texStatsPrev; };
texture texStatsCurr { Width = 1; Height = 1; Format = RGBA16F; };
sampler samplerStatsCurr { Texture = texStatsCurr; };

float4 PS_CalcStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float avg = 0; float mx = 0;
    for(int i=0; i<4; i++) for(int j=0; j<4; j++) {
        float3 c = tex2D(ReShade::BackBuffer, uv + (float2(i,j)/4.0-0.5)*(1.0/32.0)).rgb;
        #if BUFFER_COLOR_SPACE == 2 
            c = saturate(c / 125.0);
        #endif
        float l = max(c.r, max(c.g, c.b));
        avg += l; mx = max(mx, l);
    }
    return float4(avg/16.0, mx, 0, 1);
}

float4 PS_SmoothStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float avg = 0; float mx = 0;
    for(int i=0; i<32; i++) for(int j=0; j<32; j++) {
        float2 stats = tex2D(samplerStats, float2(i, j) / 32.0).xy;
        avg += stats.x; mx = max(mx, stats.y);
    }
    avg /= 1024.0;
    float2 lastStats = tex2D(samplerStatsPrev, 0.5).xy;
    return float4(lerp(avg, lastStats.x, Smoothing_Speed), lerp(mx, lastStats.y, Smoothing_Speed), 0, 1);
}

// =============================================================================
// MAIN SHADER
// =============================================================================

float4 PS_LumaBoost(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float4 base = tex2D(ReShade::BackBuffer, uv);
    
    float2 stats = tex2D(samplerStatsCurr, 0.5).xy;
    float trigger = saturate((stats.x - APL_Threshold) * Boost_Ramp);

    float3 c = Decode(base.rgb);

    // BT.2020 Luma Coefficients
    float Y  = dot(c, float3(0.2627, 0.6780, 0.0593));
    float Cb = dot(c, float3(-0.1396, -0.3604, 0.5));
    float Cr = dot(c, float3(0.5, -0.4598, -0.0402));
    
    float linearPeak = Decode(float3(stats.y, stats.y, stats.y)).r;

    float skinMask = 0.0;
    if (Enable_Skin_Protect || Debug_Skin) {
        float chroma = length(float2(Cb, Cr));
        float hue = atan2(Cr, Cb);
        float d = abs(hue - Skin_Hue_Center); if (d > 3.14159) d = 6.28318 - d;
        skinMask = saturate(1.0 - d / Skin_Sensitivity) * saturate(chroma * 10.0);
    }

    if (Y > 0.0001 && Y < linearPeak && trigger > 0.0) {
        float normX = Y / linearPeak;
        float hump = pow(normX, Shadow_Protect) * (1.0 - normX);
        float finalBoost = Boost;
        if (Enable_Skin_Protect) finalBoost *= (1.0 - (skinMask * Skin_Protect_Strength));
        
        float lift = finalBoost * trigger * hump * linearPeak;
        float oldY = Y;
        Y += lift;

        if (Enable_Sat_Recover) {
            // UPDATED SATURATION RECOVERY
            // Instead of 1:1 scaling, we use a perceptual multiplier (ratio ^ depth).
            // This compensates for the Abney/Hunt effects in human vision.
            float satRatio = Y / max(oldY, 0.0001);
            float satFactor = pow(satRatio, 1.0 + Sat_Recover);
            
            Cb *= satFactor; 
            Cr *= satFactor;
        }
    }

    float3 outColor;
    outColor.r = Y + 1.4746 * Cr;
    outColor.g = Y - 0.1645 * Cb - 0.5714 * Cr;
    outColor.b = Y + 1.8814 * Cb;

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

float4 PS_SaveStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    return tex2D(samplerStatsCurr, 0.5);
}

technique LumaBoost {
    pass { VertexShader = PostProcessVS; PixelShader = PS_CalcStats; RenderTarget = texStats; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SmoothStats; RenderTarget = texStatsCurr; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_LumaBoost; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SaveStats; RenderTarget = texStatsPrev; }
}
