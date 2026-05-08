LumaBoost is a high-performance ReShade shader designed specifically for OLED gamers. It emulates the internal hardware logic of premium displays to counteract the aggressive Auto Brightness Limiting (ABL) often found on OLED panels, restoring the intended punch and vibrancy of HDR content.

Key Features

Dynamic ABL Curve Modeling
Uses measured monitor capability data points to calculate the exact inverse boost required to maintain brightness consistency across varying scene intensities.

Intelligent Protection Engine

   Black Anchor: Tracks the dynamic black point of each frame to ensure inky blacks remain untouched.

   Skin Protection: Uses a specialized hue mask to prevent character faces from over-brightening.

   Sky ABL Bias: Specifically targets blue/cyan sky tones to prevent them from triggering hardware dimming.

Color Volume Recovery
Employs perceptual saturation scaling (counteracting the Hunt Effect) to ensure that brightened midtones don't look washed out or foggy.

Signal-Space Contrast Recovery
Selectively restores micro-textures in boosted regions without introducing noise to the shadows.

Universal Format Support
Automatically detects and optimizes its mathematical pipeline for HDR10 (PQ), scRGB (Linear), and SDR (sRGB).

Temporal Smoothing
Cinematic transitions prevent brightness "pops" and flickering during rapid lighting changes.
Installation & Usage

   Place LumaBoost.fx in your reshade-shaders/Shaders folder.

   Open the ReShade menu and search for "LumaBoost".

   Mode Switching: To switch between Standard Mode and ABL Curve Mode, scroll to the bottom of the ReShade "Home" tab and find the "Preprocessor Definitions" section. Edit TRIGGER_MODE: set to 0 for Standard or 1 for ABL.

   Use DEBUG: Show Visual Stats to assist in calibrating your APL Threshold or verifying your Monitor Model's response.
