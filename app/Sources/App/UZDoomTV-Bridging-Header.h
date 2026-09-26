#ifndef UZDoomTV_Bridging_Header_h
#define UZDoomTV_Bridging_Header_h

// Exported by UZDoomEngine.framework (uzdoom_entry.cpp)
int uzdoom_launch(int argc, char * _Nullable * _Nonnull argv);

// Touch pad state from the iPhone controller page (UZDoomEngine.framework, i_gcjoystick.mm).
// axes: LX, LY (+1 up), RX, RY (+1 up), LT, RT (0..1); buttons: bit N = KEY_PAD_DPAD_UP + N.
void uzdoom_set_touch_pad(const float * _Nullable axes, unsigned int buttons, int connected);

#endif /* UZDoomTV_Bridging_Header_h */
