// iOS host bridge (main-thread guest loop).
// SDL3/UIKit require UI on the main thread, so this host boots the guest on the
// main thread and steps frames via ballpad_ios_host_step_frame() driven by a
// SwiftUI timer/display link. Each step runs ~DEFAULT_FRAME_BLOCKS guest blocks
// then presents via Aurora (vsync-paced).
#include "ballpad_ios_host.h"
#include "ballpad_pad.h"

extern "C" {
#include "generated.h"
#include "gxruntime/aurora_backend.h"
#include "gxruntime/boot.h"
#include "gxruntime/dvd.h"
#include "gxruntime/loader.h"
#include "gxruntime/platform.h"
#include "gxruntime/efb_access.h"
#include "host/audio.h"
#include "host/mmio.h"
#include "host/hle.h"
#include "host/interrupt.h"
}

#include <SDL3/SDL_init.h>
#include <SDL3/SDL_video.h>

#include <atomic>
#include <cstdio>
#include <cstring>
#include <string>

extern "C" void ballpad_window_set_scene(void* scene);
extern "C" void* ballpad_window_get_sdl_window(void);
extern "C" void ballpad_window_force_presentable(void);
extern "C" void ballpad_ios_host_attach_sdl_view(void*);
extern "C" void SDL_SetMainReady(void);
extern "C" bool aurora_begin_frame(void);
extern "C" void aurora_end_frame(void);
extern "C" void ballpad_arm_efb_readback(void);

namespace {
std::atomic<bool> g_started{false};
std::atomic<bool> g_stop{false};
void* g_scene = nullptr;
void* g_sdl_window = nullptr;

CPUState g_cpu;
bool g_cpu_valid = false;
bool g_aurora_up = false;
unsigned long long g_blocks = 0;
const char* g_stop_reason = "";
const unsigned long long kFrameBlocks = 350000ull;
const unsigned long long kMaxBlocks = 8000000000ull;

const char* g_iso_path = nullptr;
const char* g_dol_path = nullptr;
} // namespace

void ballpad_ios_host_set_window_scene(void* uiWindowScene) { g_scene = uiWindowScene; }

void* ballpad_ios_host_sdl_uikit_window(void) { return g_sdl_window; }

static void instruction_fallback(CPUState* ctx, u32 raw, u32 cia) {
  if ((raw >> 26) == 31u) {
    const u32 xo = (raw >> 1) & 0x3FFu;
    if (xo == 982u || xo == 86u || xo == 54u || xo == 470u || xo == 467u) {
      ctx->pc = cia + 4u;
      return;
    }
    if (xo == 339u) {
      ctx->gpr[(raw >> 21) & 31u] = 0;
      ctx->pc = cia + 4u;
      return;
    }
  }
  std::fprintf(stderr, "[fallback] unhandled instruction 0x%08X at 0x%08X\n", raw, cia);
  ctx->exception |= PPC_EXC_PROGRAM;
}

bool ballpad_ios_host_start(const BallpadIosHostConfig* cfg) {
  if (g_started.load()) return true;
  setvbuf(stderr, NULL, _IONBF, 0);
  setvbuf(stdout, NULL, _IONBF, 0);

  // Resolve default asset paths from the app sandbox Documents dir.
  char docs[1024] = {0};
  if (cfg->iso_path == nullptr || cfg->dol_path == nullptr) {
    FILE* f = popen("echo $HOME/Documents", "r");
    if (f) {
      if (fgets(docs, sizeof(docs), f)) {
        docs[strcspn(docs, "\n")] = 0;
      }
      pclose(f);
    }
  }
  g_iso_path = cfg->iso_path ? strdup(cfg->iso_path)
                             : strdup((std::string(docs) + "/game.iso").c_str());
  g_dol_path = cfg->dol_path ? strdup(cfg->dol_path)
                             : strdup((std::string(docs) + "/main.dol").c_str());

  SDL_SetMainReady();
  if (g_scene != nullptr) ballpad_window_set_scene(g_scene);

  const AuroraBackendConfig backend_config = {
      .app_name = "Ballpad",
      .window_width = 1280,
      .window_height = 960,
      .vsync = true,
      .allow_texture_dumps = false,
      .info_logging = cfg->verbose,
      .graphics_logging = cfg->verbose,
      .force_untextured = false,
  };
  if (!dol_aurora_initialize(0, nullptr, &backend_config)) {
    std::fprintf(stderr, "[ballpad-ios] aurora init failed\n");
    return false;
  }
  g_aurora_up = true;
  ballpad_arm_efb_readback();
  ballpad_window_force_presentable();
  g_sdl_window = ballpad_window_get_sdl_window();
  // Open a frame packet and KEEP it open: guest GX writes during boot must
  // land in a live frame (mirrors dol_aurora_initialize on desktop, which
  // leaves g_frame_open true). Present cycles close/reopen it.
  const bool frame_ok = aurora_begin_frame();
  std::fprintf(stderr, "[ballpad-ios] open frame at init=%d\n", frame_ok ? 1 : 0);

  CPUState* cpu = &g_cpu;
  if (!cpu_init(cpu)) { return false; }
  DolLayout layout;
  if (!dol_load_into_ram(cpu, g_dol_path, &layout)) {
    std::fprintf(stderr, "[ballpad-ios] dol load failed: %s\n", g_dol_path);
    return false;
  }
  boot_setup_os_globals(cpu, &layout);
  if (!mmio_install(cpu)) { return false; }
  mmio_attach_efb_readback();
  hle_install(cpu);
  if (cfg->card_path && cfg->card_path[0]) {
    if (!hle_card_open(cfg->card_path))
      std::fprintf(stderr, "[card] slot A unavailable; continuing with no card\n");
  }
  dvd_open_image(g_iso_path);
  mmio_set_disc_present(dvd_image_ready());
  cpu->instruction_fallback = instruction_fallback;
  cpu->pc = layout.entry_point;
  g_cpu_valid = true;
  g_blocks = 0;
  g_stop = false;
  g_started = true;
  std::fprintf(stderr, "[ballpad-ios] booted entry=0x%08X\n", cpu->pc);
  return true;
}

// Steps one frame of guest work. Must be called on the main thread.
void ballpad_ios_host_step_frame(void) {
  if (!g_started.load() || !g_cpu_valid) return;
  CPUState* cpu = &g_cpu;
  unsigned long long until = g_blocks + kFrameBlocks;
  while (g_blocks < until && g_blocks < kMaxBlocks && !g_stop.load()) {
    if (dol_platform_should_quit()) { g_stop_reason = "window closed"; break; }
    interrupt_poll(cpu);
    hle_poll_callback(cpu);
    u32 pc = cpu->pc;
    if (!dolrecomp_call(cpu, pc)) {
      g_stop_reason = "pc left recompiled code";
      std::fprintf(stderr, "[run] left recompiled code: pc=0x%08X\n", cpu->pc);
      break;
    }
    if (cpu->exception) {
      if (cpu->exception == PPC_EXC_SYSTEM_CALL) {
        cpu->exception = 0;
        ppc_rfi(cpu, cpu->pc);
        continue;
      }
      g_stop_reason = "cpu exception";
      break;
    }
    g_blocks++;
  }
  if (g_blocks >= kMaxBlocks && !g_stop_reason[0]) g_stop_reason = "max-blocks watchdog";
  if (g_sdl_window != nullptr) {
    ballpad_ios_host_attach_sdl_view(g_sdl_window);
  }
  if (g_stop_reason[0]) {
    static bool s_reported = false;
    if (!s_reported) {
      s_reported = true;
      std::fprintf(stderr, "[ballpad-ios] stopped: %s blocks=%llu pc=0x%08X exc=%u\n",
                   g_stop_reason, g_blocks, cpu->pc, (unsigned)cpu->exception);
    }
  }
}

void ballpad_ios_host_stop(void) {
  g_stop = true;
  if (g_aurora_up) {
    dol_aurora_flush_gap_report();
    dol_aurora_shutdown();
    g_aurora_up = false;
  }
  g_started = false;
  g_cpu_valid = false;
}

bool ballpad_ios_host_running(void) { return g_started.load(); }

void ballpad_ios_host_application_did_become_active(void) {}
void ballpad_ios_host_application_will_resign_active(void) {}
bool ballpad_ios_host_frame_size(uint32_t* w, uint32_t* h) {
  if (!g_started.load() || w == nullptr || h == nullptr) return false;
  DolEfbAccess* efb = mmio_efb();
  if (efb == nullptr || efb->color == nullptr || efb->fill_count == 0u) return false;
  *w = efb->width;
  *h = efb->height;
  return *w > 0u && *h > 0u;
}

bool ballpad_ios_host_take_frame(uint8_t* rgba_out, uint32_t* w, uint32_t* h) {
  if (!g_started.load() || rgba_out == nullptr || w == nullptr || h == nullptr)
    return false;
  // Read the latest present-source RGBA8 frame from the software EFB backing
  // filled by the aurora readback hook (mmio_attach_efb_readback).
  DolEfbAccess* efb = mmio_efb();
  static unsigned long long s_last_fill = 0;
  if (efb->fill_count != s_last_fill) {
    s_last_fill = efb->fill_count;
    std::fprintf(stderr, "[ballpad-ios] efb fill=%llu %ux%u color=%p\n",
                 (unsigned long long)efb->fill_count, efb->width, efb->height,
                 (void*)efb->color);
  }
  if (efb == nullptr || efb->color == nullptr || efb->fill_count == 0u)
    return false;
  // Debug: dump one frame to the sandbox for inspection.
  static bool s_dumped = false;
  if (!s_dumped && efb->fill_count > 50u) {
    s_dumped = true;
    FILE* f = fopen("/Users/chrissotraidis/GitHub/ballpad/work/tmp/ios_frame.rgba", "wb");
    if (f) {
      const u32 fw = efb->width, fh = efb->height;
      for (u32 i = 0; i < fw * fh; ++i) {
        const u32 argb = efb->color[i];
        const uint8_t px[4] = {(uint8_t)(argb >> 16), (uint8_t)(argb >> 8),
                               (uint8_t)(argb), (uint8_t)(argb >> 24)};
        fwrite(px, 1, 4, f);
      }
      fclose(f);
      std::fprintf(stderr, "[ballpad-ios] dumped frame %ux%u fill=%llu\n",
                   fw, fh, (unsigned long long)efb->fill_count);
    }
  }
  const u32 fw = efb->width;
  const u32 fh = efb->height;
  if (fw == 0u || fh == 0u)
    return false;
  // Copy ARGB -> RGBA tightly packed.
  for (u32 i = 0; i < fw * fh; ++i) {
    const u32 argb = efb->color[i];
    rgba_out[i * 4u + 0u] = (uint8_t)(argb >> 16);
    rgba_out[i * 4u + 1u] = (uint8_t)(argb >> 8);
    rgba_out[i * 4u + 2u] = (uint8_t)(argb);
    rgba_out[i * 4u + 3u] = (uint8_t)(argb >> 24);
  }
  *w = fw;
  *h = fh;
  return true;
}

/* marker file_scope attach decl */
