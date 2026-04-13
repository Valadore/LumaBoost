# LumaBoost
  
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
