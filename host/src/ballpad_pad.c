#include "ballpad_pad.h"
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

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
  static int s_pad_log = -1;
  if (s_pad_log < 0)
    s_pad_log = getenv("BALLPAD_PAD_LOG") != NULL ? 1 : 0;
  if (s_pad_log) {
    static BallPadStatus s_last;
    static bool s_last_valid = false;
    if (!s_last_valid || memcmp(&s_last, status, sizeof s_last) != 0) {
      s_last = *status;
      s_last_valid = true;
      fprintf(stderr, "[pad-set] btn=0x%04X stick=%d,%d c=%d,%d L=%u R=%u err=%d\n",
              status->button, status->stickX, status->stickY,
              status->substickX, status->substickY,
              status->triggerLeft, status->triggerRight, status->err);
    }
  }
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
    static unsigned long long merge_count = 0;
    if ((++merge_count % 300000ull) == 0u)
        fprintf(stderr, "[pad] merge calls=%llu\n", merge_count);
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
