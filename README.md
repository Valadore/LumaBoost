LumaBoost
Professional EOTF and Brightness Compensation for HDR/SDR OLED Gaming

LumaBoost is a high-fidelity display-hardware emulator designed to counteract the aggressive Auto Brightness Limiting (ABL) found on OLED panels. By dynamically lifting midtones based on real-time screen analysis, it restores the intended punch and vibrancy of your HDR experience without blowing out highlights or washing out blacks.
Key Features

Dynamic ABL Curve Modeling
Uses hardware-specific data points to calculate the exact inverse boost required to maintain brightness consistency across varying scene intensities.

Dynamic Black Anchor
Automatically tracks the frame's specific black point to ensure inky blacks and intended contrast remain 100% untouched.

Specular Immunity
Intelligent logic prevents tiny bright glints (like sun reflections or light bulbs) from suppressing the global world boost.

Color Volume Recovery
Employs perceptual saturation scaling (The Hunt Effect) to ensure that brightened midtones stay vivid and detailed instead of looking foggy.

Signal-Space Contrast Recovery
Selectively restores micro-textures specifically in the areas being boosted, preventing the "flattening" effect of EOTF lifting.

Universal Format Support
Native, format-aware processing for HDR10 (PQ), scRGB (Linear), and SDR (sRGB).
Installation

    Download LumaBoost.fx.

    Place the file into your game's reshade-shaders/Shaders folder.

    Launch the game and enable LumaBoost in the ReShade overlay.

    [IMPORTANT]
    LumaBoost works best when your game's internal HDR calibration is matched to your monitor's 1% peak capability (e.g., set the game to 1000 nits if your P001 value is ~1000).

Configuration and Modes

LumaBoost offers two distinct logic engines. You can switch between them at the bottom of the ReShade Home tab under the Preprocessor Definitions section.
1. ABL Curve Mode (TRIGGER_MODE 1)

The hardware-accurate mode that uses a mathematical model of your specific monitor.

    Usage: Enter your monitor's measured nits at various window sizes (1% to 100%).

    Benefit: The shader calculates the exact light deficit caused by your panel's ABL and adds precisely that amount back.

2. Standard Mode (TRIGGER_MODE 0)

The traditional manual threshold mode.

    Usage: Set a manual APL Threshold. When the screen brightness (Green bar in stats) passes your threshold (Red line), the boost activates.

Advanced Diagnostics

Enable these tools in the menu to fine-tune your calibration:

    Visual Stats: Real-time bars showing APL (Green), Threshold (Red), Dynamic Range Floor/Peak (Blue), and Active Boost Intensity (Orange).

    Boost Heatmap: A false-color overlay showing exactly which pixels are being brightened (Red) and which are being protected (Black).

    Skin Mask: Turns detected skin purple to verify that character faces are being protected from over-brightening.
