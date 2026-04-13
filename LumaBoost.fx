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
// UI CONTROLS
// =============================================================================

uniform float APL_Threshold <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "APL Trigger Threshold";
    ui_tooltip = "At what average screen brightness should the boost start? (Default 0.25). Tune so the RED line is just past the GREEN bar in normal scenes.";
> = 0.25;

uniform float Boost <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 2.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Max Boost Strength";
    ui_tooltip = "How much to lift the midtones when the APL threshold is met.";
> = 0.5;

uniform float Boost_Ramp <
    ui_type = "slider";
    ui_min = 1.0; ui_max = 20.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Boost Activation Sensitivity";
    ui_tooltip = "Controls how aggressively the boost reaches full power after passing the threshold. Higher is more instant.";
> = 10.0;

uniform float Smoothing_Speed <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 0.99;
    ui_category = "1. Main Boost Settings";
    ui_label = "Temporal Smoothing";
    ui_tooltip = "0.0 = Instant, 0.9 = Cinematic. Higher values prevent brightness 'flickering' by smoothing the transitions.";
> = 0.90;

uniform float Shadow_Protect <
    ui_type = "slider";
    ui_min = 1.0; ui_max = 10.0;
    ui_category = "1. Main Boost Settings";
    ui_label = "Shadow Protect";
    ui_tooltip = "Higher values keep shadows and blacks dark, pushing the boost strictly into the brighter midtones.";
> = 1.0;

uniform bool Enable_Sat_Recover <
    ui_category = "2. Color Correction";
    ui_label = "Enable Saturation Recovery";
> = true;

uniform float Sat_Recover <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_category = "2. Color Correction";
    ui_label = "Recovery Amount";
> = 0.15;

uniform bool Enable_Skin_Protect <
    ui_category = "3. Skin Protection";
    ui_label = "Enable Skin Protection";
> = true;

uniform float Skin_Protect_Strength <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 1.0;
    ui_category = "3. Skin Protection";
    ui_label = "Protection Strength";
> = 0.50;

uniform float Skin_Hue_Center <
    ui_type = "slider";
    ui_min = 0.0; ui_max = 3.14;
    ui_category = "3. Skin Protection";
    ui_label = "Hue Center";
> = 2.25;

uniform float Skin_Sensitivity <
    ui_type = "slider";
    ui_min = 0.05; ui_max = 1.0;
    ui_category = "3. Skin Protection";
    ui_label = "Mask Width";
> = 0.25;

uniform bool Debug_Skin < ui_category = "4. Debug Tools"; ui_label = "DEBUG: Show Skin Mask"; > = false;
uniform bool Show_Debug < 
    ui_category = "4. Debug Tools"; 
    ui_label = "Show Visual Stats"; 
    ui_tooltip = "TOP BAR: Screen Brightness (Green) vs Threshold (Red Line).\nMIDDLE BAR: Frame Peak Anchor (Blue).\nBOTTOM BAR: Current Boost Strength (Orange).";
> = false;

// =============================================================================
// STORAGE & SAMPLING
// =============================================================================

texture texStats { Width = 32; Height = 32; Format = RGBA16F; };
sampler samplerStats { Texture = texStats; };

texture texStatsPrev { Width = 1; Height = 1; Format = RGBA16F; };
sampler samplerStatsPrev { Texture = texStatsPrev; };

texture texStatsCurr { Width = 1; Height = 1; Format = RGBA16F; };
sampler samplerStatsCurr { Texture = texStatsCurr; };

// =============================================================================
// SHADER LOGIC
// =============================================================================

// Pass 1: Find local brightness
float4 PS_CalcStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float avg = 0; float mx = 0;
    for(int i=0; i<4; i++) for(int j=0; j<4; j++) {
        float3 c = tex2D(ReShade::BackBuffer, uv + (float2(i,j)/4.0-0.5)*(1.0/32.0)).rgb;
        float l = max(c.r, max(c.g, c.b));
        avg += l; mx = max(mx, l);
    }
    return float4(avg/16.0, mx, 0, 1);
}

// Pass 2: Global APL and Temporal Smoothing
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

// Pass 3: The Midtone Boost
float4 PS_LumaBoost(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    float4 base = tex2D(ReShade::BackBuffer, uv);
    float3 c = base.rgb;

    // Convert to BT.2020 YUV
    float Y  = dot(c, float3(0.2627, 0.6780, 0.0593));
    float Cb = dot(c, float3(-0.1396, -0.3604, 0.5));
    float Cr = dot(c, float3(0.5, -0.4598, -0.0402));
    
    float2 stats = tex2D(samplerStatsCurr, 0.5).xy;
    float currentAPL = stats.x;
    float currentPeak = stats.y;

    float trigger = saturate((currentAPL - APL_Threshold) * Boost_Ramp);
    
    float skinMask = 0.0;
    if (Enable_Skin_Protect || Debug_Skin) {
        float chroma = length(float2(Cb, Cr));
        float hue = atan2(Cr, Cb);
        float d = abs(hue - Skin_Hue_Center); if (d > 3.14159) d = 6.28318 - d;
        skinMask = saturate(1.0 - d / Skin_Sensitivity) * saturate(chroma * 10.0);
    }

    if (Y > 0.001 && Y < currentPeak && trigger > 0.0) {
        float normX = Y / currentPeak;
        float hump = pow(normX, Shadow_Protect) * (1.0 - normX);
        float finalBoost = Boost;
        if (Enable_Skin_Protect) finalBoost *= (1.0 - (skinMask * Skin_Protect_Strength));
        float lift = finalBoost * trigger * hump * currentPeak;
        Y += lift;
        if (Enable_Sat_Recover) {
            float satFactor = (1.0 + (lift / (max(Y, 0.001))) * Sat_Recover);
            Cb *= satFactor; Cr *= satFactor;
        }
    }

    float3 outColor;
    outColor.r = Y + 1.4746 * Cr;
    outColor.g = Y - 0.1645 * Cb - 0.5714 * Cr;
    outColor.b = Y + 1.8814 * Cb;

    if (Debug_Skin) outColor = lerp(outColor, float3(1, 0, 1), skinMask);

    if (Show_Debug) {
        if (uv.y < 0.02) {
            if (uv.x < currentAPL) outColor = float3(0, 0.4, 0);
            if (abs(uv.x - APL_Threshold) < 0.001) outColor = float3(0.6, 0, 0);
        }
        if (uv.y > 0.022 && uv.y < 0.042 && uv.x < currentPeak) outColor = float3(0, 0.1, 0.4);
        if (uv.y > 0.044 && uv.y < 0.064 && uv.x < (trigger * Boost / 2.0)) outColor = float3(0.5, 0.3, 0);
    }
    return float4(outColor, base.a);
}

// Pass 4: Save temporal data
float4 PS_SaveStats(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target {
    return tex2D(samplerStatsCurr, 0.5);
}

// =============================================================================
// PIPELINE
// =============================================================================

technique LumaBoost {
    pass { VertexShader = PostProcessVS; PixelShader = PS_CalcStats; RenderTarget = texStats; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SmoothStats; RenderTarget = texStatsCurr; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_LumaBoost; }
    pass { VertexShader = PostProcessVS; PixelShader = PS_SaveStats; RenderTarget = texStatsPrev; }
}