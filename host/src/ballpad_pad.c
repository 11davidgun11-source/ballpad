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
