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
extern "C" void ballpad_window_hide(void);
extern "C" void ballpad_ios_host_attach_sdl_view(void*);
extern "C" void SDL_SetMainReady(void);
extern "C" bool aurora_begin_frame(void);
extern "C" void aurora_end_frame(void);
extern "C" void ballpad_arm_efb_readback(void);
extern "C" void ballpad_window_probe(void);
extern "C" unsigned long long g_dec_deliveries;

namespace {
// Redirect stderr to a host file when BALLPAD_LOG_FILE is set. The simulator
// console-pty pipe is small; the efb-fill + present log spam fills it and the
// app's fprintf(stderr) blocks forever, freezing the guest loop.
struct StderrRedirect {
  StderrRedirect() {
    const char* path = getenv("BALLPAD_LOG_FILE");
    if (path != nullptr && path[0] != '\0')
      freopen(path, "w", stderr);
  }
};
StderrRedirect s_stderr_redirect;
} // namespace

namespace {
std::atomic<bool> g_started{false};
std::atomic<bool> g_stop{false};
std::atomic<bool> g_starting{false};
void* g_scene = nullptr;
void* g_sdl_window = nullptr;

CPUState g_cpu;
bool g_cpu_valid = false;
bool g_aurora_up = false;
unsigned long long g_blocks = 0;
const char* g_stop_reason = "";
const unsigned long long kFrameBlocks = 350000ull;
const unsigned long long kMaxBlocks = 80000000000ull;

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
  if (g_aurora_up) return true;  // SwiftUI may remount the host view
  bool expected = false;
  if (!g_starting.compare_exchange_strong(expected, true))
    return true;  // another makeUIView already booting
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
    g_starting.store(false);
    return false;
  }
  g_aurora_up = true;
  g_starting.store(false);
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
    if ((g_blocks % 1000000ull) == 0u)
      std::fprintf(stderr, "[ballpad-ios] blocks=%llu pc=0x%08X msr=0x%08X dec=%u\n",
                   (unsigned long long)g_blocks, cpu->pc, cpu->msr, cpu->spr[22]);
    if (g_blocks >= 5500000000ull && (g_blocks % 100000ull) == 0u &&
        cpu->pc != 0x80259294u && cpu->pc != 0x8025929Cu &&
        cpu->pc != 0x80259298u && cpu->pc != 0x802592A0u &&
        getenv("BALLPAD_DEBUG_THREADS") != nullptr)
      std::fprintf(stderr, "[loadpc] b=%llu pc=0x%08X\n",
                   (unsigned long long)g_blocks, cpu->pc);
    if ((g_blocks % 2500000ull) == 0u) {
      ballpad_window_probe();
    }
  }
  if (g_blocks >= kMaxBlocks && !g_stop_reason[0]) g_stop_reason = "max-blocks watchdog";
  if (g_sdl_window != nullptr) {
    ballpad_ios_host_attach_sdl_view(g_sdl_window);
  }
  // Debug: dump guest OS thread states during the match-load zone to find what
  // the loading threads wait on (BALLPAD_DEBUG_THREADS=1).
  if (getenv("BALLPAD_DEBUG_THREADS") != nullptr && g_blocks >= 2500000000ull &&
      (g_blocks % 200000000ull) < 1000000ull) {
    // Save a screen-history snapshot every 400M blocks for offline review.
    if ((g_blocks % 400000000ull) == 0u) {
      DolEfbAccess* efb = mmio_efb();
      if (efb != nullptr && efb->color != nullptr && efb->fill_count > 0u) {
        char path[128];
        std::snprintf(path, sizeof path,
                      "/Users/chrissotraidis/GitHub/ballpad/work/tmp/snap_%llu.rgba",
                      (unsigned long long)g_blocks);
        FILE* f = fopen(path, "wb");
        if (f) {
          const u32 fw = efb->width, fh = efb->height;
          for (u32 i = 0; i < fw * fh; ++i) {
            const u32 argb = efb->color[i];
            const uint8_t px[4] = {(uint8_t)(argb >> 16), (uint8_t)(argb >> 8),
                                   (uint8_t)(argb), (uint8_t)(argb >> 24)};
            fwrite(px, 1, 4, f);
          }
          fclose(f);
        }
      }
    }
    static unsigned long long s_last_dump_blocks = 0;
    if (g_blocks - s_last_dump_blocks >= 200000000ull) {
      s_last_dump_blocks = g_blocks;
      const u32 first = 0x80348230u;  // DefaultThread (OSThread)
      u32 t = first;
      std::fprintf(stderr, "[threads] dump at blocks=%llu rqbits@747a8=%08X @747b8=%08X\n",
                   (unsigned long long)g_blocks,
                   mem_read32(cpu, 0x803747A8u), mem_read32(cpu, 0x803747B8u));
      std::fprintf(stderr, "[threads] retraceCount=%u retraceQueue={h=%08X t=%08X} alarm={h=%08X t=%08X} curThread=0x%08X\n",
                   mem_read32(cpu, 0x8037480Cu),
                   mem_read32(cpu, 0x80374814u), mem_read32(cpu, 0x80374818u),
                   mem_read32(cpu, 0x80374720u), mem_read32(cpu, 0x80374724u),
                   mem_read32(cpu, 0x800000DCu));
      const u32 alarmHead = mem_read32(cpu, 0x80374720u);
      std::fprintf(stderr, "[threads] tb=%llu decDeliveries=%llu dec=%u alarmHead=0x%08X fire=%llu period=%llu handler=0x%08X\n",
                   (unsigned long long)cpu->timebase,
                   (unsigned long long)g_dec_deliveries, cpu->spr[22],
                   alarmHead,
                   alarmHead ? (unsigned long long)mem_read64(cpu, alarmHead + 0x08u) : 0ull,
                   alarmHead ? (unsigned long long)mem_read64(cpu, alarmHead + 0x10u) : 0ull,
                   alarmHead ? mem_read32(cpu, alarmHead + 0x18u) : 0u);
      std::fprintf(stderr, "[threads] sebringPkg=%08X curResLoading=%08X feResMgr=%08X feSceneMgr=%08X\n",
                   mem_read32(cpu, 0x80374410u), mem_read32(cpu, 0x80374434u),
                   mem_read32(cpu, 0x80374448u), mem_read32(cpu, 0x80374450u));
      const u32 tt = mem_read32(cpu, 0x80373DA0u);      // TransitionTask*
      const u32 lm = tt ? mem_read32(cpu, tt + 0x28u) : 0u;  // LoadingManager*
      std::fprintf(stderr, "[threads] transTask=0x%08X state=%u loadMgr=0x%08X cur=%u num=%u fin=%u q=0x%08X\n",
                   tt, tt ? mem_read32(cpu, tt + 0x2Cu) : 0xFFFFFFFFu,
                   lm,
                   lm ? mem_read32(cpu, lm + 0x1Cu) : 0u,
                   lm ? mem_read32(cpu, lm + 0x20u) : 0u,
                   lm ? mem_read32(cpu, lm + 0x28u) : 0u,
                   lm ? mem_read32(cpu, lm + 0x24u) : 0u);
      // Match clocks (ClockManager active list).
      u32 clk = mem_read32(cpu, 0x8037446Cu);  // m_activeList head
      for (int ci = 0; ci < 6 && clk != 0u && clk >= 0x80000000u; ci++) {
        float fTimer = 0.f, fEnd = 0.f;
        const u32 uTimer = mem_read32(cpu, clk + 0x08u);
        const u32 uEnd = mem_read32(cpu, clk + 0x0Cu);
        memcpy(&fTimer, &uTimer, 4);
        memcpy(&fEnd, &uEnd, 4);
        std::fprintf(stderr, "[threads] clock=0x%08X state=%u timer=%.1f end=%.1f\n",
                     clk, mem_read32(cpu, clk + 0x18u), fTimer, fEnd);
        clk = mem_read32(cpu, clk + 0x24u);
      }
      const u32 game = mem_read32(cpu, 0x80373708u);  // g_pGame (cGame*)
      const u32 gameClock = game ? mem_read32(cpu, game + 0x0Cu) : 0u;
      std::fprintf(stderr, "[threads] cGame=0x%08X state=%d gameClock=0x%08X\n",
                   game, game ? (int)mem_read32(cpu, game + 0x24u) : -1, gameClock);
      std::fprintf(stderr, "[threads] feStateCur=%d feStatePending=%d\n",
                   (int)mem_read32(cpu, 0x80395408u), (int)mem_read32(cpu, 0x8039540Cu));
      std::fprintf(stderr, "[threads] menuType=%d feSceneMgr=0x%08X topScene=0x%08X vtab=0x%08X\n",
                   (int)mem_read32(cpu, 0x803713D4u),
                   mem_read32(cpu, 0x80374450u),
                   mem_read32(cpu, 0x80374450u) ? mem_read32(cpu, mem_read32(cpu, 0x80374450u) + 0x1Cu) : 0u,
                   0u);
      const u32 taskMgr = mem_read32(cpu, 0x803742B8u);  // nlTaskManager*
      std::fprintf(stderr, "[threads] taskMgr=0x%08X currState=%u pendingState=%u locked=%u\n",
                   taskMgr,
                   taskMgr ? mem_read32(cpu, taskMgr + 0x08u) : 0u,
                   taskMgr ? mem_read32(cpu, taskMgr + 0x0Cu) : 0u,
                   taskMgr ? mem_read32(cpu, taskMgr + 0x10u) : 0u);
      if (gameClock != 0u && gameClock >= 0x80000000u) {
        float fTimer = 0.f, fEnd = 0.f;
        const u32 uTimer = mem_read32(cpu, gameClock + 0x08u);
        const u32 uEnd = mem_read32(cpu, gameClock + 0x0Cu);
        memcpy(&fTimer, &uTimer, 4);
        memcpy(&fEnd, &uEnd, 4);
        std::fprintf(stderr, "[threads] gameClock state=%u timer=%.1f end=%.1f\n",
                     mem_read32(cpu, gameClock + 0x18u), fTimer, fEnd);
      }
      for (int rq = 0; rq < 4; rq++) {
        const u32 q = 0x80347E18u + (u32)rq * 8u;
        const u32 h = mem_read32(cpu, q);
        if (h != 0u)
          std::fprintf(stderr, "[threads] runq[%d]={h=%08X t=%08X}\n", rq,
                       h, mem_read32(cpu, q + 4u));
      }
      for (int i = 0; i < 24; i++) {
        const u32 state = mem_read16(cpu, t + 0x2C8u);
        const u32 queue = mem_read32(cpu, t + 0x2DCu);
        const u32 srr0 = mem_read32(cpu, t + 0x198u);
        const u32 prio = mem_read32(cpu, t + 0x2D0u);
        const u32 next = mem_read32(cpu, t + 0x2FCu);  // linkActive.next
        std::fprintf(stderr, "[threads] t=0x%08X state=%u prio=%d waitq=0x%08X pc=0x%08X next=0x%08X\n",
                     t, state, (int)prio, queue, srr0, next);
        if (next == first || next == 0u || next < 0x80000000u || next > 0x81000000u) break;
        t = next;
      }
    }
  }
  // Auto-input: navigate to a match (BALLPAD_AUTOSTART=1).
  // Guest-block-paced phase machine verified against the Path C (RecompCore)
  // oracle on macOS. The guest advances 350000 blocks per presented frame, so
  // block thresholds are platform-independent guest-time anchors:
  //   boot -> health ~1.15B, mem check ~1.3B, save prompt ~1.45B,
  //   title ~2.2B, main menu ~2.6B, team select ~3.8B, match start ~4.8B.
  // Each phase holds a PAD state for hold_blocks, then releases; steps advance
  // at the at_blocks threshold (the loop neutralizes between steps).
  static bool s_autostart = [] {
    const char* v = getenv("BALLPAD_AUTOSTART");
    return v != nullptr && v[0] != '\0' && v[0] != '0';
  }();
  if (s_autostart) {
    struct AutoStep { u16 button; int sx, sy; unsigned long long hold_blocks, at_blocks; };
    static const AutoStep kAutoSteps[] = {
        // 0: boot wait; guest reaches the health screen on its own.
        {0x0000, 0, 0, 0, 1150000000ull},
        // A past the health screen (~1.15B); A past the memory-card check.
        {0x0100, 0, 0, 20000000ull, 1300000000ull},
        {0x0100, 0, 0, 20000000ull, 1450000000ull},
        // CONTINUE WITHOUT SAVING (save creation hangs on the chassis oracle).
        {0x0004, 0, 0, 15000000ull, 1500000000ull},
        {0x0100, 0, 0, 20000000ull, 2200000000ull},
        // Title -> main menu.
        {0x1000, 0, 0, 20000000ull, 2600000000ull},
        // GRUDGE MATCH -> captain select -> sidekick select -> CPU captain grid.
        {0x0100, 0, 0, 20000000ull, 3000000000ull},
        {0x0100, 0, 0, 20000000ull, 3400000000ull},
        {0x0100, 0, 0, 20000000ull, 3800000000ull},
        // CPU captain choice (left) -> CPU sidekick grid -> controller screen.
        {0x0001, 0, 0, 15000000ull, 3900000000ull},
        {0x0100, 0, 0, 20000000ull, 4300000000ull},
        {0x0100, 0, 0, 20000000ull, 4700000000ull},
        // Assign P1 to the left team -> match. Screen arrival drifts run to
        // run, so retry on a cadence: (D_LEFT, A) covers the side-choice
        // screen; a lone A confirms the stadium card (D_LEFT would move the
        // carousel). Once the match starts the inputs are harmless.
        {0x0001, 0, 0, 15000000ull, 5400000000ull},
        {0x0100, 0, 0, 20000000ull, 5500000000ull},
        {0x0100, 0, 0, 20000000ull, 6000000000ull},
        {0x0001, 0, 0, 15000000ull, 6800000000ull},
        {0x0100, 0, 0, 20000000ull, 6900000000ull},
        {0x0100, 0, 0, 20000000ull, 7500000000ull},
        {0x0001, 0, 0, 15000000ull, 8200000000ull},
        {0x0100, 0, 0, 20000000ull, 8300000000ull},
        {0x0100, 0, 0, 20000000ull, 9000000000ull},
    };
    static const unsigned kAutoCount =
        static_cast<unsigned>(sizeof(kAutoSteps) / sizeof(kAutoSteps[0]));
    static unsigned s_auto_phase = 0;
    static bool s_auto_holding = false;
    static unsigned long long s_auto_hold_start = 0;
    const AutoStep& st = kAutoSteps[s_auto_phase < kAutoCount ? s_auto_phase : kAutoCount - 1];
    if (s_auto_phase >= kAutoCount) {
      // Done: keep the pad neutral.
      BallPadStatus s{};
      ballpad_pad_get(0, &s);
      s.button = 0; s.stickX = 0; s.stickY = 0; s.err = 0;
      ballpad_pad_set(0, &s);
    } else {
      BallPadStatus s{};
      s.err = 0;
      if (g_blocks >= st.at_blocks) {
        if (!s_auto_holding) {
          s_auto_holding = true;
          s_auto_hold_start = g_blocks;
          std::fprintf(stderr, "[ballpad-ios] autostart step=%u/%u btn=0x%04X at=%llu\n",
                       s_auto_phase, kAutoCount, st.button, (unsigned long long)st.at_blocks);
        }
        if (g_blocks - s_auto_hold_start < st.hold_blocks) {
          s.button = st.button;
          s.stickX = (s8)st.sx; s.stickY = (s8)st.sy;
        } else {
          ++s_auto_phase;
          s_auto_holding = false;
        }
      }
      ballpad_pad_set(0, &s);
      if (s_auto_phase >= kAutoCount) {
        std::fprintf(stderr, "[ballpad-ios] autostart complete at blocks=%llu\n",
                     (unsigned long long)g_blocks);
      }
    }
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
  // Debug: dump a frame periodically for inspection.
  static unsigned long long s_dump_prev = 0;
  if (efb->fill_count - s_dump_prev >= 60u && efb->fill_count > 30u) {
    s_dump_prev = efb->fill_count;
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
