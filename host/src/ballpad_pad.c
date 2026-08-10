#include "ballpad_pad.h"
#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct BallPadPort {
  BallPadStatus touch;
  BallPadStatus controller;
  uint16_t touch_latched;
  uint16_t controller_latched;
} BallPadPort;

static BallPadPort g_ports[4];
static pthread_mutex_t g_pad_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_once_t g_pad_once = PTHREAD_ONCE_INIT;
static pthread_once_t g_pad_log_once = PTHREAD_ONCE_INIT;
static int g_pad_log = 0;
static BallPadStatus g_last_logged;
static bool g_last_logged_valid = false;

static void initialize_pads(void) {
  for (int i = 0; i < 4; ++i) {
    memset(&g_ports[i], 0, sizeof(g_ports[i]));
    g_ports[i].touch.err = -1;
    g_ports[i].controller.err = -1;
  }
}

static void ensure_init(void) {
  pthread_once(&g_pad_once, initialize_pads);
}

static void initialize_pad_log(void) {
  g_pad_log = getenv("BALLPAD_PAD_LOG") != NULL ? 1 : 0;
}

static int8_t strongest_axis(int8_t a, int8_t b) {
  const int aa = a < 0 ? -(int)a : (int)a;
  const int bb = b < 0 ? -(int)b : (int)b;
  return bb > aa ? b : a;
}

static void merge_port(const BallPadPort* port, BallPadStatus* out) {
  const bool touch_connected = port->touch.err == 0;
  const bool controller_connected = port->controller.err == 0;
  memset(out, 0, sizeof(*out));
  if (!touch_connected && !controller_connected) {
    out->err = -1;
    return;
  }
  const BallPadStatus zero = {0};
  const BallPadStatus* touch = touch_connected ? &port->touch : &zero;
  const BallPadStatus* controller = controller_connected ? &port->controller : &zero;
  out->button = touch->button | controller->button |
                port->touch_latched | port->controller_latched;
  out->stickX = strongest_axis(touch->stickX, controller->stickX);
  out->stickY = strongest_axis(touch->stickY, controller->stickY);
  out->substickX = strongest_axis(touch->substickX, controller->substickX);
  out->substickY = strongest_axis(touch->substickY, controller->substickY);
  out->triggerLeft = touch->triggerLeft > controller->triggerLeft
                         ? touch->triggerLeft : controller->triggerLeft;
  out->triggerRight = touch->triggerRight > controller->triggerRight
                          ? touch->triggerRight : controller->triggerRight;
  out->analogA = touch->analogA > controller->analogA
                     ? touch->analogA : controller->analogA;
  out->analogB = touch->analogB > controller->analogB
                     ? touch->analogB : controller->analogB;
  out->err = 0;
}

static void set_source(int port, const BallPadStatus* status, bool controller) {
  ensure_init();
  if (port < 0 || port > 3 || status == NULL) return;
  pthread_mutex_lock(&g_pad_mutex);
  BallPadPort* pad = &g_ports[port];
  BallPadStatus* previous = controller ? &pad->controller : &pad->touch;
  uint16_t* latched = controller ? &pad->controller_latched : &pad->touch_latched;
  *latched |= status->button & (uint16_t)~previous->button;
  *previous = *status;
  pthread_mutex_unlock(&g_pad_mutex);
}

void ballpad_pad_set(int port, const BallPadStatus* status) {
  set_source(port, status, false);
  pthread_once(&g_pad_log_once, initialize_pad_log);
  if (g_pad_log && port >= 0 && port <= 3 && status != NULL) {
    pthread_mutex_lock(&g_pad_mutex);
    if (!g_last_logged_valid ||
        memcmp(&g_last_logged, status, sizeof g_last_logged) != 0) {
      g_last_logged = *status;
      g_last_logged_valid = true;
      fprintf(stderr, "[pad-set] btn=0x%04X stick=%d,%d c=%d,%d L=%u R=%u err=%d\n",
              status->button, status->stickX, status->stickY,
              status->substickX, status->substickY,
              status->triggerLeft, status->triggerRight, status->err);
    }
    pthread_mutex_unlock(&g_pad_mutex);
  }
}

void ballpad_pad_set_controller(int port, const BallPadStatus* status) {
  set_source(port, status, true);
}

void ballpad_pad_clear(int port) {
  ensure_init();
  if (port < 0 || port > 3) return;
  pthread_mutex_lock(&g_pad_mutex);
  memset(&g_ports[port], 0, sizeof(g_ports[port]));
  g_ports[port].touch.err = -1;
  g_ports[port].controller.err = -1;
  pthread_mutex_unlock(&g_pad_mutex);
}

void ballpad_pad_clear_touch(int port) {
  ensure_init();
  if (port < 0 || port > 3) return;
  pthread_mutex_lock(&g_pad_mutex);
  memset(&g_ports[port].touch, 0, sizeof(g_ports[port].touch));
  g_ports[port].touch.err = -1;
  g_ports[port].touch_latched = 0;
  pthread_mutex_unlock(&g_pad_mutex);
}

void ballpad_pad_clear_controller(int port) {
  ensure_init();
  if (port < 0 || port > 3) return;
  pthread_mutex_lock(&g_pad_mutex);
  memset(&g_ports[port].controller, 0, sizeof(g_ports[port].controller));
  g_ports[port].controller.err = -1;
  g_ports[port].controller_latched = 0;
  pthread_mutex_unlock(&g_pad_mutex);
}

void ballpad_pad_get(int port, BallPadStatus* out) {
  ensure_init();
  if (out == NULL) return;
  if (port < 0 || port > 3) {
    memset(out, 0, sizeof(*out));
    out->err = -1;
    return;
  }
  pthread_mutex_lock(&g_pad_mutex);
  merge_port(&g_ports[port], out);
  pthread_mutex_unlock(&g_pad_mutex);
}

static void ballpad_pad_consume(int port, BallPadStatus* out) {
  ensure_init();
  if (out == NULL) return;
  if (port < 0 || port > 3) {
    memset(out, 0, sizeof(*out));
    out->err = -1;
    return;
  }
  pthread_mutex_lock(&g_pad_mutex);
  merge_port(&g_ports[port], out);
  g_ports[port].touch_latched = 0;
  g_ports[port].controller_latched = 0;
  pthread_mutex_unlock(&g_pad_mutex);
}

#include "gxruntime/platform.h"

/* Merge hook called from Aurora's pad_read (platform ops). Returns 1 when the
 * virtual touch pad for `port` is active (err == 0) and fills *out with the
 * DolPadState-compatible fields. */
int ballpad_host_pad_merge(int port, DolPadState* out) {
    static unsigned long long merge_count = 0;
    static int merge_log = -1;
    if (merge_log < 0)
        merge_log = getenv("BALLPAD_PAD_LOG") != NULL ? 1 : 0;
    if (merge_log && (++merge_count % 300000ull) == 0u)
        fprintf(stderr, "[pad] merge calls=%llu\n", merge_count);
    if (port != 0 || out == NULL)
        return 0;
    BallPadStatus s;
    ballpad_pad_consume(0, &s);
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
