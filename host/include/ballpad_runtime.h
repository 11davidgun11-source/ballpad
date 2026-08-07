#pragma once
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct BallpadRuntimeConfig {
  const char* iso_path;   /* optional; may be NULL on iOS until user import */
  const char* dol_path;   /* optional path to main.dol */
  int enable_runtime;     /* 0 = shell-only */
} BallpadRuntimeConfig;

bool ballpad_runtime_init(const BallpadRuntimeConfig* cfg);
void ballpad_runtime_shutdown(void);
void ballpad_runtime_frame(void);
const char* ballpad_runtime_banner(void);

#ifdef __cplusplus
}
#endif
