#include "ballpad_runtime.h"
#include "ballpad_pad.h"
#include <cstdio>
#include <cstring>

static bool g_inited = false;
static bool g_enable = false;

const char* ballpad_runtime_banner(void) {
  return "[ballpad] runtime init";
}

bool ballpad_runtime_init(const BallpadRuntimeConfig* cfg) {
  g_enable = cfg && cfg->enable_runtime;
  g_inited = true;
  std::fprintf(stderr, "%s enable=%d\n", ballpad_runtime_banner(), g_enable ? 1 : 0);
  // Full GXRuntime/Strikers host wiring lands in Steps 7-8.
  return true;
}

void ballpad_runtime_shutdown(void) {
  g_inited = false;
  g_enable = false;
}

void ballpad_runtime_frame(void) {
  if (!g_inited) return;
  // Frame contract: sample touches -> ballpad_pad_set -> runtime.frame
  // Guest integration arrives with AOT link (Step 7+).
  (void)g_enable;
}
