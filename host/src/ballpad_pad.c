#include "ballpad_pad.h"
#include <string.h>

static BallPadStatus g_pads[4];
static int g_initialized = 0;

static void ensure_init(void) {
  if (g_initialized) return;
  for (int i = 0; i < 4; ++i) {
    memset(&g_pads[i], 0, sizeof(g_pads[i]));
    g_pads[i].err = -1; /* disconnected until set */
  }
  g_initialized = 1;
}

void ballpad_pad_set(int port, const BallPadStatus* status) {
  ensure_init();
  if (port < 0 || port > 3 || status == NULL) return;
  g_pads[port] = *status;
}

void ballpad_pad_clear(int port) {
  ensure_init();
  if (port < 0 || port > 3) return;
  memset(&g_pads[port], 0, sizeof(g_pads[port]));
  g_pads[port].err = -1;
}

void ballpad_pad_get(int port, BallPadStatus* out) {
  ensure_init();
  if (out == NULL) return;
  if (port < 0 || port > 3) {
    memset(out, 0, sizeof(*out));
    out->err = -1;
    return;
  }
  *out = g_pads[port];
}

#include "gxruntime/platform.h"

/* Merge hook called from Aurora's pad_read (platform ops). Returns 1 when the
 * virtual touch pad for `port` is active (err == 0) and fills *out with the
 * DolPadState-compatible fields. */
int ballpad_host_pad_merge(int port, DolPadState* out) {
    if (port != 0 || out == NULL)
        return 0;
    BallPadStatus s;
    ballpad_pad_get(0, &s);
    if (s.err != 0)
        return 0;
    out->button = s.button;
    out->stick_x = s.stickX;
    out->stick_y = s.stickY;
    out->substick_x = s.substickX;
    out->substick_y = s.substickY;
    out->trigger_left = s.triggerLeft;
    out->trigger_right = s.triggerRight;
    out->analog_a = s.analogA;
    out->analog_b = s.analogB;
    out->error = 0;
    return 1;
}
