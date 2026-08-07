#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BallPadStatus {
  uint16_t button;
  int8_t stickX;
  int8_t stickY;
  int8_t substickX;
  int8_t substickY;
  uint8_t triggerLeft;
  uint8_t triggerRight;
  uint8_t analogA;
  uint8_t analogB;
  int8_t err; /* 0 = PAD_ERR_NONE, -1 = no controller */
} BallPadStatus;

/* port: 0..3. MVP uses port 0 only. */
void ballpad_pad_set(int port, const BallPadStatus* status);
void ballpad_pad_clear(int port);
void ballpad_pad_get(int port, BallPadStatus* out); /* for tests */

/* Aurora/Dolphin-compatible button masks */
enum {
  BALLPAD_BUTTON_LEFT  = 0x0001,
  BALLPAD_BUTTON_RIGHT = 0x0002,
  BALLPAD_BUTTON_DOWN  = 0x0004,
  BALLPAD_BUTTON_UP    = 0x0008,
  BALLPAD_TRIGGER_Z    = 0x0010,
  BALLPAD_TRIGGER_R    = 0x0020,
  BALLPAD_TRIGGER_L    = 0x0040,
  BALLPAD_BUTTON_A     = 0x0100,
  BALLPAD_BUTTON_B     = 0x0200,
  BALLPAD_BUTTON_X     = 0x0400,
  BALLPAD_BUTTON_Y     = 0x0800,
  BALLPAD_BUTTON_START = 0x1000
};

#ifdef __cplusplus
}
#endif
