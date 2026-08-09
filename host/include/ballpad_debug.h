#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* D2: forensic/debug tooling for the iOS host, extracted out of
 * ballpad_ios_host.cpp. Every feature here is env-gated and off in shipped
 * runs (BALLPAD_DEBUG_THREADS, BALLPAD_DEBUG_EFB, BALLPAD_EFB_POKE,
 * BALLPAD_WINDOW_PROBE). Call sites are one cheap per-step hook in the host.
 */

typedef struct CPUState CPUState;
typedef struct DolEfbAccess DolEfbAccess;

/* Per-step hook (called once per guest step): guest-task run counters,
 * the 1M-block progress log, the load-pc sampler, the SDL window probe, and
 * the periodic guest OS thread-state dump. `blocks` is the guest block count.
 * All of it is no-op unless BALLPAD_DEBUG_THREADS (or the probe env) is set.
 */
void ballpad_debug_step(CPUState* cpu, unsigned long long blocks);

/* EFB readback diagnostics: per-fill log (BALLPAD_DEBUG_EFB) and the
 * one-shot pixel poke test with readback dumps (BALLPAD_EFB_POKE). Called
 * from the frame-read path with the live software EFB backing. */
void ballpad_debug_efb_fill(DolEfbAccess* efb);

#ifdef __cplusplus
}
#endif
