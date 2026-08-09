// iOS host bridge (main-thread guest loop).
// SDL3/UIKit require UI on the main thread, so this host boots the guest on the
// main thread and steps frames via ballpad_ios_host_step_frame() driven by a
// SwiftUI timer/display link. Each step runs ~DEFAULT_FRAME_BLOCKS guest blocks
// then presents via Aurora (vsync-paced).
#include "ballpad_ios_host.h"
#include "ballpad_pad.h"

extern "C" {
#include "generated.h"
#include "gxruntime/aram.h"
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
#include "host/audio.h"
}

#include <SDL3/SDL_init.h>
#include <SDL3/SDL_video.h>

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <vector>

extern "C" void ballpad_window_set_scene(void* scene);
extern "C" void* ballpad_window_get_sdl_window(void);
extern "C" void ballpad_window_force_presentable(void);
extern "C" void ballpad_window_hide(void);
extern "C" void ballpad_ios_host_attach_sdl_view(void*);
extern "C" void SDL_SetMainReady(void);
extern "C" bool aurora_begin_frame(void);
extern "C" void aurora_end_frame(void);
extern "C" unsigned long long aurora_present_count(void);
extern "C" void aurora_set_efb_scale(uint32_t scale);
extern "C" void ballpad_arm_efb_readback(void);
extern "C" void ballpad_window_probe(void);
extern "C" void aram_save(void* dst);
extern "C" void aram_restore(const void* src);
extern "C" uint32_t interrupt_save_state_size(void);
extern "C" void interrupt_save_state(void* dst);
extern "C" void interrupt_restore_state(const void* src);
extern "C" uint32_t mmio_save_state_size(void);
extern "C" void mmio_save_state(void* dst);
extern "C" void mmio_restore_state(const void* src);
extern "C" bool dol_aurora_frontend_save_state(void* dst, uint32_t* size);
extern "C" bool dol_aurora_frontend_restore_state(const void* src,
                                                  uint32_t size);
extern "C" bool dol_aurora_gxcore_save_state(void* dst, uint32_t* size);
extern "C" bool dol_aurora_gxcore_restore_state(const void* src,
                                                uint32_t size);
extern "C" unsigned long long g_dec_deliveries;

namespace {
// Redirect stderr to a host file when BALLPAD_LOG_FILE is set. The simulator
// console-pty pipe is small; the efb-fill + present log spam fills it and the
// app's fprintf(stderr) blocks forever, freezing the guest loop.
struct StderrRedirect {
  StderrRedirect() {
    const char* path = getenv("BALLPAD_LOG_FILE");
    if (path != nullptr && path[0] != '\0') {
      std::string resolved = path;
      if (resolved.rfind("$HOME", 0) == 0) {
        char home[1024] = {0};
        FILE* f = popen("echo $HOME", "r");
        if (f) {
          if (fgets(home, sizeof(home), f))
            home[strcspn(home, "\n")] = 0;
          pclose(f);
        }
        resolved.replace(0, 5, home);
      }
      freopen(resolved.c_str(), "w", stderr);
    }
  }
};
StderrRedirect s_stderr_redirect;
} // namespace

namespace {
std::atomic<bool> g_started{false};
std::atomic<bool> g_stop{false};
std::atomic<bool> g_starting{false};
std::atomic<bool> g_paused{false};
std::thread g_guest_thread;
std::mutex g_frame_mutex;

void* g_scene = nullptr;
void* g_sdl_window = nullptr;

CPUState g_cpu;
bool g_cpu_valid = false;
bool g_aurora_up = false;
unsigned long long g_blocks = 0;
// B1: adaptive per-step block budget. The guest worker measures each step's
// wall time and nudges this toward a ~16.6 ms slice, so light scenes run more
// blocks per step (up to the fps cap) and heavy scenes degrade gracefully
// instead of over-running a fixed 350K budget.
unsigned long long g_frame_blocks = 350000ull;
const char* g_stop_reason = "";
const unsigned long long kMaxBlocks = 80000000000ull;
int g_efb_scale = 1;

const char* g_iso_path = nullptr;
const char* g_dol_path = nullptr;
const char* g_card_path = nullptr;
bool g_quickbooted = false;
} // namespace

// ---- A1 quick-boot savestate (resume a match on cold launch) ----
namespace {
constexpr char kQuickbootMagic[4] = {'B', 'P', 'S', 'V'};
constexpr uint32_t kQuickbootVersion = 3;
constexpr uint32_t kQuickbootHeaderSize = 64;

// File layout (host byte order): header, CPU registers block, CPU scalar tail,
// guest RAM, ARAM, interrupt runtime blob, MMIO runtime blob.
struct QuickbootHeader {
  char magic[4];
  uint32_t version;
  uint32_t header_size;
  uint64_t saved_blocks;
  uint32_t cpu_regs_size;  // [0, offsetof(CPUState, external_read))
  uint32_t cpu_tail_size;  // [offsetof(CPUState, ram), sizeof(CPUState))
  uint32_t ram_size;
  uint32_t aram_size;
  uint32_t interrupt_size;
  uint32_t mmio_size;
  uint32_t frontend_size;
  uint32_t gxcore_size;
  uint32_t reserved[2];
};

std::string quickboot_documents_dir() {
  char docs[1024] = {0};
  FILE* f = popen("echo $HOME/Documents", "r");
  if (f) {
    if (fgets(docs, sizeof(docs), f))
      docs[strcspn(docs, "\n")] = 0;
    pclose(f);
  }
  return std::string(docs);
}

std::string quickboot_path() {
  return quickboot_documents_dir() + "/QuickBoot.bss";
}

bool quickboot_file_exists(const char* path) {
  struct stat st;
  return path != nullptr && stat(path, &st) == 0 && S_ISREG(st.st_mode);
}
} // namespace

// Capture the running match into Documents/QuickBoot.bss. The image covers
// everything a resume needs: CPU registers, guest RAM, ARAM, and the
// host-side interrupt/MMIO device state (see interrupt_save_state /
// mmio_save_state / aram_save).
bool ballpad_ios_host_save_quickboot(void) {
  if (!g_started.load() || !g_cpu_valid)
    return false;
  CPUState* cpu = &g_cpu;
  const uint32_t cpuRegsSize = (uint32_t)offsetof(CPUState, external_read);
  const uint32_t cpuTailSize =
      (uint32_t)(sizeof(CPUState) - offsetof(CPUState, ram));
  const uint32_t ramSize = cpu->ram_size;
  const uint32_t aramSize = ARAM_SIZE;
  const uint32_t interruptSize = interrupt_save_state_size();
  const uint32_t mmioSize = mmio_save_state_size();
  uint32_t frontendSize = 0;
  dol_aurora_frontend_save_state(nullptr, &frontendSize);
  uint32_t gxcoreSize = 0;
  dol_aurora_gxcore_save_state(nullptr, &gxcoreSize);

  QuickbootHeader h;
  memset(&h, 0, sizeof h);
  memcpy(h.magic, kQuickbootMagic, 4);
  h.version = kQuickbootVersion;
  h.header_size = kQuickbootHeaderSize;
  h.saved_blocks = g_blocks;
  h.cpu_regs_size = cpuRegsSize;
  h.cpu_tail_size = cpuTailSize;
  h.ram_size = ramSize;
  h.aram_size = aramSize;
  h.interrupt_size = interruptSize;
  h.mmio_size = mmioSize;
  h.frontend_size = frontendSize;
  h.gxcore_size = gxcoreSize;

  const std::string path = quickboot_path();
  FILE* f = fopen(path.c_str(), "wb");
  if (f == nullptr) {
    std::fprintf(stderr, "[quickboot] save failed to open %s\n", path.c_str());
    return false;
  }
  const auto t0 = std::chrono::steady_clock::now();
  bool ok = true;
  ok = ok && fwrite(&h, 1, sizeof h, f) == sizeof h;
  ok = ok && fwrite((const char*)cpu, 1, cpuRegsSize, f) == cpuRegsSize;
  ok = ok && fwrite((const char*)cpu + offsetof(CPUState, ram), 1,
                    cpuTailSize, f) == cpuTailSize;
  ok = ok && fwrite(cpu->ram, 1, ramSize, f) == ramSize;
  std::vector<uint8_t> aram(aramSize);
  aram_save(aram.data());
  ok = ok && fwrite(aram.data(), 1, aramSize, f) == aramSize;
  std::vector<uint8_t> ib(interruptSize);
  interrupt_save_state(ib.data());
  ok = ok && fwrite(ib.data(), 1, interruptSize, f) == interruptSize;
  std::vector<uint8_t> mb(mmioSize);
  mmio_save_state(mb.data());
  ok = ok && fwrite(mb.data(), 1, mmioSize, f) == mmioSize;
  std::vector<uint8_t> fb(frontendSize);
  if (frontendSize != 0u) {
    ok = ok && dol_aurora_frontend_save_state(fb.data(), &frontendSize) &&
               fwrite(fb.data(), 1, frontendSize, f) == frontendSize;
  }
  std::vector<uint8_t> gb(gxcoreSize);
  if (gxcoreSize != 0u) {
    ok = ok && dol_aurora_gxcore_save_state(gb.data(), &gxcoreSize) &&
               fwrite(gb.data(), 1, gxcoreSize, f) == gxcoreSize;
  }
  fclose(f);
  if (!ok) {
    remove(path.c_str());
    std::fprintf(stderr, "[quickboot] save write error\n");
    return false;
  }
  const double ms = std::chrono::duration<double, std::milli>(
                        std::chrono::steady_clock::now() - t0)
                        .count();
  std::fprintf(stderr,
               "[quickboot] saved %s (%u+%u+%u+%u+%u+%u+%u+%u bytes, "
               "%llu blocks) "
               "in %.1f ms\n",
               path.c_str(), (unsigned)cpuRegsSize, (unsigned)cpuTailSize,
               (unsigned)ramSize, (unsigned)aramSize, (unsigned)interruptSize,
               (unsigned)mmioSize, (unsigned)frontendSize, (unsigned)gxcoreSize,
               (unsigned long long)g_blocks, ms);
  return true;
}

bool ballpad_ios_host_quickbooted(void) { return g_quickbooted; }

// ---- A2 in-app game import (document picker -> game.iso + main.dol) ----
bool ballpad_ios_host_game_files_present(void) {
  const std::string dir = quickboot_documents_dir();
  struct stat st;
  const std::string iso = dir + "/game.iso";
  const std::string dol = dir + "/main.dol";
  return stat(iso.c_str(), &st) == 0 && S_ISREG(st.st_mode) &&
         stat(dol.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

namespace {
// GameCube disc header: DOL offset/FST offset/FST size at 0x420..0x42B.
// The DOL's own header sizes live at the DolRecomp-extract layout (text sizes
// at 0x90+i*4, data offsets at 0x1C+i*4, data sizes at 0xAC+i*4).
uint32_t qb_read_be32(const uint8_t* p) {
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
         ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

bool stream_copy(FILE* in, FILE* out, uint64_t bytes) {
  char buf[1 << 16];
  uint64_t done = 0;
  while (bytes == ~0ull || done < bytes) {
    const size_t want = (bytes == ~0ull)
                            ? sizeof buf
                            : (size_t)((bytes - done) < sizeof buf
                                           ? bytes - done
                                           : sizeof buf);
    const size_t got = fread(buf, 1, want, in);
    if (got == 0)
      return bytes == ~0ull || done >= bytes;
    if (fwrite(buf, 1, got, out) != got)
      return false;
    done += got;
  }
  return true;
}

uint32_t dol_file_size_from_header(const uint8_t* h) {
  uint32_t max_end = 0x100u;
  for (uint32_t i = 0; i < 7; ++i) {
    const uint32_t off = qb_read_be32(h + i * 4u);
    const uint32_t size = qb_read_be32(h + 0x90u + i * 4u);
    if (size != 0u && off + size > max_end)
      max_end = off + size;
  }
  for (uint32_t i = 0; i < 11u; ++i) {
    const uint32_t off = qb_read_be32(h + 0x1Cu + i * 4u);
    const uint32_t size = qb_read_be32(h + 0xACu + i * 4u);
    if (size != 0u && off + size > max_end)
      max_end = off + size;
  }
  return max_end;
}
} // namespace

bool ballpad_ios_host_import_game(const char* iso_path) {
  if (iso_path == nullptr || iso_path[0] == '\0')
    return false;
  const std::string dir = quickboot_documents_dir();
  FILE* in = fopen(iso_path, "rb");
  if (in == nullptr) {
    std::fprintf(stderr, "[import] cannot open %s\n", iso_path);
    return false;
  }
  const std::string isoDest = dir + "/game.iso";
  const std::string dolDest = dir + "/main.dol";
  const std::string isoTmp = isoDest + ".tmp";
  const std::string dolTmp = dolDest + ".tmp";

  bool ok = true;
  // Copy the disc image.
  FILE* out = fopen(isoTmp.c_str(), "wb");
  if (out == nullptr) {
    std::fprintf(stderr, "[import] cannot write %s\n", isoTmp.c_str());
    fclose(in);
    return false;
  }
  ok = stream_copy(in, out, ~0ull);
  fclose(out);
  if (!ok) {
    std::fprintf(stderr, "[import] iso copy failed\n");
    fclose(in);
    remove(isoTmp.c_str());
    return false;
  }

  // Extract sys/main.dol from the disc header + DOL section table.
  uint8_t discHeader[0x430];
  if (fseek(in, 0, SEEK_SET) != 0 ||
      fread(discHeader, 1, sizeof discHeader, in) != sizeof discHeader) {
    std::fprintf(stderr, "[import] disc header read failed\n");
    ok = false;
  }
  const uint32_t dolOffset = qb_read_be32(discHeader + 0x420u);
  if (ok && (dolOffset == 0u || dolOffset < 0x100u)) {
    std::fprintf(stderr, "[import] bad dol offset 0x%X\n", dolOffset);
    ok = false;
  }
  uint8_t dolHeader[0x100];
  if (ok && (fseek(in, dolOffset, SEEK_SET) != 0 ||
             fread(dolHeader, 1, sizeof dolHeader, in) != sizeof dolHeader)) {
    std::fprintf(stderr, "[import] dol header read failed\n");
    ok = false;
  }
  const uint32_t dolSize = ok ? dol_file_size_from_header(dolHeader) : 0u;
  if (ok && (dolSize < 0x100u)) {
    std::fprintf(stderr, "[import] bad dol size %u\n", dolSize);
    ok = false;
  }
  if (ok) {
    FILE* dout = fopen(dolTmp.c_str(), "wb");
    if (dout == nullptr || fseek(in, dolOffset, SEEK_SET) != 0 ||
        !stream_copy(in, dout, dolSize)) {
      std::fprintf(stderr, "[import] dol extract failed\n");
      ok = false;
    }
    fclose(dout);
  }
  fclose(in);

  if (!ok) {
    remove(isoTmp.c_str());
    remove(dolTmp.c_str());
    return false;
  }
  // Atomic-ish rename (best effort).
  if (rename(isoTmp.c_str(), isoDest.c_str()) != 0 ||
      rename(dolTmp.c_str(), dolDest.c_str()) != 0) {
    remove(isoTmp.c_str());
    remove(dolTmp.c_str());
    std::fprintf(stderr, "[import] rename failed\n");
    return false;
  }
  std::fprintf(stderr, "[import] game imported: iso -> %s dol -> %s "
                       "(dolSize=%u)\n",
               isoDest.c_str(), dolDest.c_str(), dolSize);
  return true;
}

// Part 1 of a quick-boot restore: CPU registers + guest RAM. Runs before
// mmio_install so the install re-wires the session's external-memory hooks.
static bool quickboot_restore_cpu(CPUState* cpu) {
  const std::string path = quickboot_path();
  if (!quickboot_file_exists(path.c_str()))
    return false;
  FILE* f = fopen(path.c_str(), "rb");
  if (f == nullptr)
    return false;
  QuickbootHeader h;
  bool ok = fread(&h, 1, sizeof h, f) == sizeof h;
  ok = ok && memcmp(h.magic, kQuickbootMagic, 4) == 0;
  ok = ok && h.version == kQuickbootVersion;
  ok = ok && h.header_size == kQuickbootHeaderSize;
  const uint32_t cpuRegsSize = (uint32_t)offsetof(CPUState, external_read);
  const uint32_t cpuTailSize =
      (uint32_t)(sizeof(CPUState) - offsetof(CPUState, ram));
  ok = ok && h.cpu_regs_size == cpuRegsSize && h.cpu_tail_size == cpuTailSize;
  ok = ok && h.ram_size == cpu->ram_size && h.aram_size == ARAM_SIZE;
  ok = ok && h.interrupt_size == interrupt_save_state_size();
  ok = ok && h.mmio_size == mmio_save_state_size();
  uint32_t frontendSize = 0;
  dol_aurora_frontend_save_state(nullptr, &frontendSize);
  ok = ok && h.frontend_size == frontendSize;
  uint32_t gxcoreSize = 0;
  dol_aurora_gxcore_save_state(nullptr, &gxcoreSize);
  ok = ok && h.gxcore_size == gxcoreSize;
  if (!ok) {
    fclose(f);
    std::fprintf(stderr, "[quickboot] restore: header mismatch, ignoring\n");
    return false;
  }
  // Keep this session's memory pointers; the captured tail carried stale ones.
  u8* sessionRam = cpu->ram;
  u8* sessionMem2 = cpu->mem2;
  const u32 sessionRamSize = cpu->ram_size;
  const u32 sessionMem2Size = cpu->mem2_size;
  ok = ok && fread((char*)cpu, 1, cpuRegsSize, f) == cpuRegsSize;
  ok = ok && fread((char*)cpu + offsetof(CPUState, ram), 1, cpuTailSize, f) ==
                 cpuTailSize;
  cpu->ram = sessionRam;
  cpu->mem2 = sessionMem2;
  cpu->ram_size = sessionRamSize;
  cpu->mem2_size = sessionMem2Size;
  ok = ok && fread(cpu->ram, 1, cpu->ram_size, f) == cpu->ram_size;
  fclose(f);
  if (!ok) {
    std::fprintf(stderr, "[quickboot] restore: read error, ignoring\n");
    return false;
  }
  g_blocks = h.saved_blocks;
  g_quickbooted = true;
  return true;
}

// Part 2 of a quick-boot restore: ARAM + interrupt/MMIO runtime blobs. Runs
// after mmio_install (which re-inits the devices and zeroes ARAM) so the
// captured device state wins over the fresh init.
static bool quickboot_restore_runtime(void) {
  const std::string path = quickboot_path();
  FILE* f = fopen(path.c_str(), "rb");
  if (f == nullptr)
    return false;
  QuickbootHeader h;
  bool ok = fread(&h, 1, sizeof h, f) == sizeof h;
  if (!ok || memcmp(h.magic, kQuickbootMagic, 4) != 0 ||
      h.version != kQuickbootVersion) {
    fclose(f);
    return false;
  }
  const long dataOff = (long)(h.header_size + h.cpu_regs_size +
                              h.cpu_tail_size + h.ram_size);
  ok = ok && fseek(f, dataOff, SEEK_SET) == 0;
  std::vector<uint8_t> aram(h.aram_size);
  ok = ok && fread(aram.data(), 1, h.aram_size, f) == h.aram_size;
  std::vector<uint8_t> ib(h.interrupt_size);
  ok = ok && fread(ib.data(), 1, h.interrupt_size, f) == h.interrupt_size;
  std::vector<uint8_t> mb(h.mmio_size);
  ok = ok && fread(mb.data(), 1, h.mmio_size, f) == h.mmio_size;
  std::vector<uint8_t> fb(h.frontend_size);
  ok = ok && fread(fb.data(), 1, h.frontend_size, f) == h.frontend_size;
  std::vector<uint8_t> gb(h.gxcore_size);
  ok = ok && fread(gb.data(), 1, h.gxcore_size, f) == h.gxcore_size;
  fclose(f);
  if (!ok)
    return false;
  aram_restore(aram.data());
  interrupt_restore_state(ib.data());
  mmio_restore_state(mb.data());
  if (!dol_aurora_frontend_restore_state(fb.data(), h.frontend_size))
    return false;
  if (!dol_aurora_gxcore_restore_state(gb.data(), h.gxcore_size))
    return false;
  return true;
}

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

static void guest_loop();

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
  // M11: virtual memory card lives in the app's Documents/Saves (user-visible
  // in the Files app for import/export). The memory-card runtime creates the
  // container on first open.
  static std::string s_card_path;
  if (cfg->card_path && cfg->card_path[0]) {
    s_card_path = cfg->card_path;
  } else {
    std::string savesDir = std::string(docs) + "/Saves";
    mkdir(savesDir.c_str(), 0755);
    s_card_path = savesDir + "/CardA.dolcard";
  }
  g_card_path = s_card_path.c_str();

  SDL_SetMainReady();
  if (g_scene != nullptr) ballpad_window_set_scene(g_scene);

  // iOS displays via EFB readback into a fixed 640x528 software backing; the
  // aurora renderer must size the EFB target to the true EFB (not the full
  // screen), otherwise the readback becomes a cropped slice of a full-screen
  // render. Make this the permanent iOS behavior (overridable for tests).
  if (getenv("BALLPAD_EFB_NATIVE") == nullptr)
    setenv("BALLPAD_EFB_NATIVE", "1", 1);
  // EFB supersample scale (M10 resolution 1x/2x/3x/4x). Applied before Aurora
  // init so the first EFB target creation uses it; set_efb_scale also handles
  // runtime changes (recreates the targets on the next surface refresh).
  if (getenv("BALLPAD_EFB_SCALE") != nullptr) {
    const int envScale = atoi(getenv("BALLPAD_EFB_SCALE"));
    if (envScale >= 1 && envScale <= 4)
      g_efb_scale = envScale;
  }
  aurora_set_efb_scale((uint32_t)g_efb_scale);

  const AuroraBackendConfig backend_config = {
      .app_name = "Ballpad",
      .window_width = 1280,
      .window_height = 960,
      // BALLPAD_VSYNC=0 disables the swapchain present fence (diagnostic: some
      // simulators stall the vsynced present for hundreds of ms per frame).
      .vsync = getenv("BALLPAD_VSYNC") == nullptr ||
               (getenv("BALLPAD_VSYNC")[0] != '0'),
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
  // Perf: no SDL audio stream on the iOS host (enable_audio=false); skip the
  // per-block audio DMA polling that would otherwise run with no output.
  audio_set_enabled(cfg->enable_audio);
  // Perf: the iOS display presents EFB-direct; the E7 XFB YUYV-to-RAM encode
  // on every display copy is never read by the guest. Disable it.
  if (getenv("BALLPAD_DISABLE_XFB_RAM") == nullptr)
    setenv("BALLPAD_DISABLE_XFB_RAM", "1", 1);
  // BALLPAD_DISABLE_READBACK=1 skips arming the continuous EFB readback
  // (diagnostic: on some simulators the readback map stalls the render worker).
  if (getenv("BALLPAD_DISABLE_READBACK") == nullptr ||
      getenv("BALLPAD_DISABLE_READBACK")[0] != '1')
    ballpad_arm_efb_readback();
  ballpad_window_force_presentable();
  g_sdl_window = ballpad_window_get_sdl_window();
  if (g_sdl_window != nullptr) {
    int w = 0, h = 0;
    SDL_GetWindowSizeInPixels(static_cast<SDL_Window*>(g_sdl_window), &w, &h);
    std::fprintf(stderr, "[ballpad-window] size=%dx%d\n", w, h);
  }
  // Open a frame packet and KEEP it open: guest GX writes during boot must
  // land in a live frame (mirrors dol_aurora_initialize on desktop, which
  // leaves g_frame_open true). Present cycles close/reopen it.
  const bool frame_ok = aurora_begin_frame();
  std::fprintf(stderr, "[ballpad-ios] open frame at init=%d\n", frame_ok ? 1 : 0);

  CPUState* cpu = &g_cpu;
  if (!cpu_init(cpu)) { return false; }
  // A1 quick-boot: when a savestate exists, resume it instead of replaying the
  // full boot. BALLPAD_NO_QUICKBOOT=1 forces a fresh boot (to capture a new
  // savestate). The CPU/regs part restores before mmio_install so the install
  // can re-wire this session's external-memory hooks; the ARAM/device blobs
  // restore afterwards (see quickboot_restore_runtime).
  bool quickboot = false;
  if (getenv("BALLPAD_NO_QUICKBOOT") == nullptr) {
    const auto t0 = std::chrono::steady_clock::now();
    quickboot = quickboot_restore_cpu(cpu);
    if (quickboot) {
      const double ms = std::chrono::duration<double, std::milli>(
                            std::chrono::steady_clock::now() - t0)
                            .count();
      std::fprintf(stderr,
                   "[quickboot] restored CPU+RAM (%u MB) in %.1f ms "
                   "blocks=%llu pc=0x%08X\n",
                   cpu->ram_size / (1024u * 1024u), ms,
                   (unsigned long long)g_blocks, cpu->pc);
    }
  }
  if (!quickboot) {
    DolLayout layout;
    if (!dol_load_into_ram(cpu, g_dol_path, &layout)) {
      std::fprintf(stderr, "[ballpad-ios] dol load failed: %s\n", g_dol_path);
      return false;
    }
    boot_setup_os_globals(cpu, &layout);
    cpu->pc = layout.entry_point;
    g_blocks = 0;
  }
  if (!mmio_install(cpu)) { return false; }
  mmio_attach_efb_readback();
  hle_install(cpu);
  if (quickboot && !quickboot_restore_runtime())
    std::fprintf(stderr, "[quickboot] runtime restore failed\n");
  if (!hle_card_open(s_card_path.c_str()))
    std::fprintf(stderr, "[card] slot A unavailable; continuing with no card\n");
  dvd_open_image(g_iso_path);
  mmio_set_disc_present(dvd_image_ready());
  cpu->instruction_fallback = instruction_fallback;
  g_cpu_valid = true;
  g_stop = false;
  g_started = true;
  std::fprintf(stderr, "[ballpad-ios] booted %s entry=0x%08X blocks=%llu\n",
               quickboot ? "from quickboot" : "fresh", cpu->pc,
               (unsigned long long)g_blocks);
  g_paused.store(false);
  if (g_guest_thread.joinable())
    g_guest_thread.join();
  g_guest_thread = std::thread(guest_loop);
  return true;
}

// Steps one frame of guest work (the block budget + presents + autostart +
// quick-boot drive). Runs on the B1 guest worker thread; the SwiftUI display
// timer no longer calls it.
static void step_guest(void) {
  if (!g_started.load() || !g_cpu_valid) return;
  // Perf instrumentation: wall-clock guest throughput per step_frame call
  // (BALLPAD_PERF_LOG=1). Reports every 60 calls (~1s at 60Hz).
  const auto t_step_begin = std::chrono::steady_clock::now();
  const unsigned long long blocks_step_begin = g_blocks;
  CPUState* cpu = &g_cpu;
  unsigned long long until = g_blocks + g_frame_blocks;
  // Hoisted once per step: the per-block debug gate used to call getenv()
  // (an unfair-lock + linear environ scan) on every guest block, which
  // consumed ~90% of the main-thread CPU and capped the guest at ~8M blocks/s.
  static const bool s_debug_threads =
      getenv("BALLPAD_DEBUG_THREADS") != nullptr;
  // Perf: replace the per-block 64-bit modulo checks with compare counters
  // (a 64-bit `%` by a non-power-of-two constant is a multi-instruction
  // multiply-shift sequence, ~15-30 cycles each, twice per guest block).
  static unsigned long long s_next_block_log = 1000000ull;
  static unsigned long long s_next_window_probe = 2500000ull;
  // Batch the window-close check: the event is rare; checking every ~100K
  // blocks (hundreds of times/sec) is more than enough.
  static unsigned long long s_next_quit_check = 100000ull;
  while (g_blocks < until && g_blocks < kMaxBlocks && !g_stop.load()) {
    if (g_blocks >= s_next_quit_check) {
      s_next_quit_check += 100000ull;
      if (dol_platform_should_quit()) {
        g_stop_reason = "window closed";
        break;
      }
    }
    interrupt_poll(cpu);
    hle_poll_callback(cpu);
    u32 pc = cpu->pc;
    // Task-run counters: which game task Runners actually execute (the pad
    // update path is suspected stuck). The entry pc is only visible before the
    // dispatch consumes it.
    if (s_debug_threads) {
      static unsigned long long s_tasks[4] = {0, 0, 0, 0};
      if (pc == 0x801D2914u) s_tasks[0]++;       // nlTaskManager::RunAllTasks
      else if (pc == 0x8016E330u) s_tasks[1]++;  // FixedUpdateTask::Run
      else if (pc == 0x8017071Cu) s_tasks[2]++;  // FrontEndTask::Run
      else if (pc == 0x80170BACu) s_tasks[3]++;  // GameRenderTask::Run
      static unsigned long long s_padcalls[2] = {0, 0};
      if (pc == 0x801C3A78u) s_padcalls[0]++;    // UpdatePlatPad
      else if (pc == 0x801C3808u) s_padcalls[1]++;  // PadStatus::Update
      if (pc == 0x8016E330u) {  // FixedUpdateTask::Run: sample per-frame ticker delta
        static u64 s_prev_tb = 0;
        static unsigned long long s_delta_samples = 0;
        if (s_prev_tb != 0u) {
          const u64 delta = cpu->timebase - s_prev_tb;
          static u64 s_delta_min = ~0ull, s_delta_max = 0, s_delta_sum = 0;
          static unsigned long long s_delta_n = 0;
          if (delta < s_delta_min) s_delta_min = delta;
          if (delta > s_delta_max) s_delta_max = delta;
          s_delta_sum += delta;
          s_delta_n++;
          if ((s_delta_n % 200u) == 0u)
            std::fprintf(stderr, "[tasks] tbDelta n=%llu min=%llu avg=%llu max=%llu\n",
                         (unsigned long long)s_delta_n, (unsigned long long)s_delta_min,
                         (unsigned long long)(s_delta_sum / s_delta_n),
                         (unsigned long long)s_delta_max);
        }
        s_prev_tb = cpu->timebase;
      }
      static unsigned long long s_task_log_at = 2000000000ull;
      if (g_blocks >= s_task_log_at) {
        s_task_log_at += 500000000ull;
        std::fprintf(stderr, "[tasks] b=%llu runAll=%llu fixed=%llu frontEnd=%llu gameRender=%llu updPlat=%llu padUpdate=%llu\n",
                     (unsigned long long)g_blocks, s_tasks[0], s_tasks[1], s_tasks[2], s_tasks[3],
                     s_padcalls[0], s_padcalls[1]);
      }
    }
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
    if (g_blocks >= s_next_block_log) {
      s_next_block_log += 1000000ull;
      std::fprintf(stderr, "[ballpad-ios] blocks=%llu pc=0x%08X msr=0x%08X dec=%u\n",
                   (unsigned long long)g_blocks, cpu->pc, cpu->msr, cpu->spr[22]);
    }
    if (g_blocks >= 5500000000ull && (g_blocks % 100000ull) == 0u &&
        cpu->pc != 0x80259294u && cpu->pc != 0x8025929Cu &&
        cpu->pc != 0x80259298u && cpu->pc != 0x802592A0u &&
        s_debug_threads)
      std::fprintf(stderr, "[loadpc] b=%llu pc=0x%08X\n",
                   (unsigned long long)g_blocks, cpu->pc);
    if (g_blocks >= s_next_window_probe) {
      s_next_window_probe += 2500000ull;
      ballpad_window_probe();
    }
  }
  if (g_blocks >= kMaxBlocks && !g_stop_reason[0]) g_stop_reason = "max-blocks watchdog";
  // Debug: dump guest OS thread states during the match-load zone to find what
  // the loading threads wait on (BALLPAD_DEBUG_THREADS=1).
  if (s_debug_threads && g_blocks >= 2500000000ull &&
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
      // Game PAD status buffers: does the guest see the injected input?
      const u32 padPtr = mem_read32(cpu, 0x80372FF0u);
      std::fprintf(stderr, "[threads] padCurPtr=0x%08X btn=0x%04X st=%d,%d err=%d padStat0=0x%04X st=%d,%d\n",
                   padPtr,
                   padPtr ? mem_read16(cpu, padPtr) : 0u,
                   padPtr ? (s8)mem_read8(cpu, padPtr + 2u) : 0,
                   padPtr ? (s8)mem_read8(cpu, padPtr + 3u) : 0,
                   padPtr ? (s8)mem_read8(cpu, padPtr + 10u) : 0,
                   mem_read16(cpu, 0x80372FF8u), (s8)mem_read8(cpu, 0x80372FFAu),
                   (s8)mem_read8(cpu, 0x80372FFBu));
      // PadStatus edge pipeline (PadStatus::Update output) + cPadManager pads.
      const u32 padStat = mem_read32(cpu, 0x80382FF8u);   // padStatus* (UpdatePlatPad lwz r13+0x9FB8)
      const u32 padObj = mem_read32(cpu, 0x80343368u);    // m_aPads[0]
      const u32 remap = mem_read32(cpu, 0x80374350u);     // m_pRemapArray
      std::fprintf(stderr, "[threads] padStat=0x%08X justPressed=0x%04X prevBtn=0x%04X prevErr=%d padObj=0x%08X connected=%u\n",
                   padStat,
                   padStat ? mem_read16(cpu, padStat + 0x380u) : 0u,
                   padStat ? mem_read16(cpu, padStat + 0x390u) : 0u,
                   padStat ? (s8)mem_read8(cpu, padStat + 0x398u) : 0,
                    padObj,
                    padObj ? mem_read8(cpu, padObj + 0x1Cu) : 0u);
      if (remap != 0u && remap >= 0x80000000u)
        std::fprintf(stderr, "[threads] remap=0x%08X [0]=%08X [1]=%08X [4]=%08X [8]=%08X\n",
                     remap, mem_read32(cpu, remap), mem_read32(cpu, remap + 4u),
                     mem_read32(cpu, remap + 16u), mem_read32(cpu, remap + 32u));
      else
        std::fprintf(stderr, "[threads] remap=0x%08X (NULL!)\n", remap);
      // GameSceneManager scene stack (SCENE_TITLE=2, MAIN_MENU=3, ...).
      const u32 gsm = mem_read32(cpu, 0x80373840u);
      const u32 gsmDepth = gsm ? mem_read32(cpu, gsm + 0x04u) : 0u;
      if (gsmDepth != 0u && gsmDepth <= 16u) {
        std::fprintf(stderr, "[threads] sceneDepth=%u top=0x%08X bottom=0x%08X\n",
                     gsmDepth, mem_read32(cpu, gsm + 0x08u + (gsmDepth - 1u) * 4u),
                     mem_read32(cpu, gsm + 0x08u));
        // If the top scene is a popup menu, read its selection + option labels.
        const u32 topScene = mem_read32(cpu, gsm + 0x08u + (gsmDepth - 1u) * 4u);
        if (topScene == 0x1Bu) {  // SCENE_POPUP_MENU
          const u32 handler = mem_read32(cpu, gsm + 0x88u + (gsmDepth - 1u) * 4u);
          const u32 numOpt = handler ? mem_read32(cpu, handler + 0xA28u + 0x14u) : 0u;
          std::fprintf(stderr, "[threads] popup handler=0x%08X hl=%d opts=%d\n",
                       handler, handler ? (int)mem_read32(cpu, handler + 0xA20u) : -1, numOpt);
          if (handler)
            std::fprintf(stderr, "[threads]   popupType=%d\n",
                         (int)mem_read32(cpu, handler + 0xA7Cu));
          // Presentation slide state (accept animation progress).
          if (handler) {
            const u32 feScene = mem_read32(cpu, handler + 0x10u);
            const u32 fePkg = feScene ? mem_read32(cpu, feScene) : 0u;
            const u32 pres = fePkg ? mem_read32(cpu, fePkg + 0x04u) : 0u;
            const u32 slide = pres ? mem_read32(cpu, pres + 0x04u) : 0u;
            float fStart = 0, fDur = 0, fTime = 0, fAccept = 0;
            if (slide) {
              const u32 uS = mem_read32(cpu, slide + 0x10u), uD = mem_read32(cpu, slide + 0x14u),
                        uT = mem_read32(cpu, slide + 0x18u);
              memcpy(&fStart, &uS, 4); memcpy(&fDur, &uD, 4); memcpy(&fTime, &uT, 4);
            }
            const u32 uA = mem_read32(cpu, handler + 0xA24u);
            memcpy(&fAccept, &uA, 4);
            std::fprintf(stderr, "[threads] popupSlide pkg=0x%08X pres=0x%08X slide=0x%08X start=%.2f dur=%.2f time=%.2f acceptDelay=%.2f\n",
                         fePkg, pres, slide, fStart, fDur, fTime, fAccept);
          }
          for (u32 oi = 0; oi < numOpt && oi < 4u; oi++) {
            const u32 labelPtr = handler ? mem_read32(cpu, handler + 0xA28u + 0x04u + oi * 4u) : 0u;
            char label[48];
            u32 lp = labelPtr;
            u32 ci = 0;
            while (lp >= 0x80000000u && ci < 46u) {
              const u16 ch = mem_read16(cpu, lp);
              if (ch == 0u || ch > 0x7Fu) break;
              label[ci++] = (char)ch;
              lp += 2u;
            }
            label[ci] = 0;
            std::fprintf(stderr, "[threads]   opt%u=%s\n", oi, labelPtr ? label : "(null)");
          }
        }
      }
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
    static AutoStep kAutoSteps[] = {
        // 0: boot wait; guest reaches the health screen on its own.
        {0x0000, 0, 0, 0, 1150000000ull},
        // A past the health screen (~1.15B); A past the memory-card check.
        {0x0100, 0, 0, 20000000ull, 1300000000ull},
        {0x0100, 0, 0, 20000000ull, 1450000000ull},
        // CONTINUE WITHOUT SAVING (save creation hangs on the chassis oracle).
        {0x0004, 0, 0, 15000000ull, 1500000000ull},
        {0x0100, 0, 0, 20000000ull, 2200000000ull},
        // The boot reaches the memcard save/load popup (option 0 = Retry
        // loops forever): D_DOWN selects "Continue without ...", A confirms.
        {0x0004, 0, 0, 15000000ull, 2500000000ull},
        {0x0100, 0, 0, 20000000ull, 2600000000ull},
        // Title advances on A (0x100) -> main menu.
        {0x0100, 0, 0, 20000000ull, 2900000000ull},
        // Match-start drive: repeat (D_LEFT, A x3, D_LEFT, A x3) on a cadence.
        // The A's advance menus/rosters; a D_LEFT that lands on the side-choice
        // screen (after a roster A chain, or right after a popup dismiss)
        // picks the left side and the following A starts the match. In-match
        // the presses are harmless (left + tackle).
        {0x0001, 0, 0, 15000000ull, 3000000000ull},
        {0x0100, 0, 0, 20000000ull, 3100000000ull},
        {0x0100, 0, 0, 20000000ull, 3200000000ull},
        {0x0100, 0, 0, 20000000ull, 3300000000ull},
        {0x0001, 0, 0, 15000000ull, 3400000000ull},
        {0x0100, 0, 0, 20000000ull, 3500000000ull},
        {0x0100, 0, 0, 20000000ull, 3600000000ull},
        {0x0100, 0, 0, 20000000ull, 3700000000ull},
        {0x0001, 0, 0, 15000000ull, 3900000000ull},
        {0x0100, 0, 0, 20000000ull, 4000000000ull},
        {0x0100, 0, 0, 20000000ull, 4100000000ull},
        {0x0100, 0, 0, 20000000ull, 4200000000ull},
        {0x0001, 0, 0, 15000000ull, 4300000000ull},
        {0x0100, 0, 0, 20000000ull, 4400000000ull},
        {0x0100, 0, 0, 20000000ull, 4500000000ull},
        {0x0100, 0, 0, 20000000ull, 4600000000ull},
        {0x0001, 0, 0, 15000000ull, 4800000000ull},
        {0x0100, 0, 0, 20000000ull, 4900000000ull},
        {0x0100, 0, 0, 20000000ull, 5000000000ull},
        {0x0100, 0, 0, 20000000ull, 5100000000ull},
        {0x0001, 0, 0, 15000000ull, 5200000000ull},
        {0x0100, 0, 0, 20000000ull, 5300000000ull},
        {0x0100, 0, 0, 20000000ull, 5400000000ull},
        {0x0100, 0, 0, 20000000ull, 5500000000ull},
        {0x0001, 0, 0, 15000000ull, 5700000000ull},
        {0x0100, 0, 0, 20000000ull, 5800000000ull},
        {0x0100, 0, 0, 20000000ull, 5900000000ull},
        {0x0100, 0, 0, 20000000ull, 6000000000ull},
        {0x0001, 0, 0, 15000000ull, 6100000000ull},
        {0x0100, 0, 0, 20000000ull, 6200000000ull},
        {0x0100, 0, 0, 20000000ull, 6300000000ull},
        {0x0100, 0, 0, 20000000ull, 6400000000ull},
        {0x0001, 0, 0, 15000000ull, 6600000000ull},
        {0x0100, 0, 0, 20000000ull, 6700000000ull},
        {0x0100, 0, 0, 20000000ull, 6800000000ull},
        {0x0100, 0, 0, 20000000ull, 6900000000ull},
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
    // A1 quick-boot: capture the savestate while the phase machine is parked
    // at the final match-start step (the game is on the side-choice /
    // stadium-card screen — a stable menu state with the DVD idle). On
    // restore, the host replays the match-start A; the match scene setup
    // re-emits the full GX state into the fresh renderer.
    // (Capturing mid-match produced a dark frame: the guest believes its GX
    // state is already set, so per-frame deltas never re-establish the
    // renderer's lights/TEV state. docs/09 2026-08-08.)
    //
    // The snapshot must be taken while the guest is parked in the OS idle
    // loop (VI retrace wait): capturing mid-render resumes the guest
    // mid-GX-command, the shadow frontend rejects the truncated stream
    // (opcode 0x23), and rendering dies (draws=0).
    static bool s_quickboot_captured = false;
    if (!s_quickboot_captured && s_auto_phase == kAutoCount - 1 &&
        !s_auto_holding &&
        (cpu->pc == 0x800051B4u || cpu->pc == 0x800051D8u)) {
      s_quickboot_captured = true;
      ballpad_ios_host_save_quickboot();
    }
  }
  // Quick-boot restore input: press the match-start A (the autostart's final
  // steps were A@6.7B/A@6.8B/A@6.9B and the capture parked the machine one A
  // short of the match) so the game starts the match from the side-choice /
  // stadium-card screen. The match scene setup re-emits the full GX state into
  // the fresh renderer (a mid-match restore skips that setup and renders
  // dark). Presses are ~100M blocks apart to match the proven autostart
  // cadence; extras are harmless once in-match.
  static bool s_qb_drive_done = false;
  if (g_quickbooted && !s_qb_drive_done) {
    static bool s_qb_drive_started = false;
    static unsigned long long s_qb_drive_blocks = 0;
    static unsigned s_qb_drive_step = 0;
    static bool s_qb_holding = false;
    if (!s_qb_drive_started) {
      s_qb_drive_started = true;
      s_qb_drive_blocks = g_blocks + 80000000ull;  // ~4 s settle
      std::fprintf(stderr, "[quickboot] driving match start\n");
    }
    if (g_blocks >= s_qb_drive_blocks && !s_qb_drive_done) {
      static const u16 kQbButtons[] = {BALLPAD_BUTTON_A, BALLPAD_BUTTON_A,
                                       BALLPAD_BUTTON_A};
      static const unsigned long long kQbSpacing[] = {
          20000000ull, 100000000ull, 100000000ull};
      BallPadStatus s{};
      s.err = 0;
      if (!s_qb_holding) {
        s_qb_holding = true;
        s_qb_drive_blocks = g_blocks + kQbSpacing[s_qb_drive_step];
        std::fprintf(stderr, "[quickboot] drive step %u btn=0x%04X\n",
                     s_qb_drive_step, kQbButtons[s_qb_drive_step]);
      }
      if (g_blocks < s_qb_drive_blocks) {
        s.button = kQbButtons[s_qb_drive_step];
      } else {
        ++s_qb_drive_step;
        s_qb_holding = false;
        if (s_qb_drive_step >= 3) {
          s_qb_drive_done = true;
          std::fprintf(stderr, "[quickboot] match-start drive complete\n");
        }
      }
      ballpad_pad_set(0, &s);
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
  static int s_perf_log = -1;
  if (s_perf_log < 0)
    s_perf_log = getenv("BALLPAD_PERF_LOG") != nullptr ? 1 : 0;
  if (s_perf_log) {
    static unsigned long long s_perf_steps = 0;
    static unsigned long long s_perf_blocks_total = 0;
    static auto s_perf_t0 = std::chrono::steady_clock::now();
    ++s_perf_steps;
    s_perf_blocks_total += g_blocks - blocks_step_begin;
    if ((s_perf_steps % 60u) == 0u) {
      const double wallMs =
          std::chrono::duration<double, std::milli>(
              std::chrono::steady_clock::now() - s_perf_t0)
              .count();
      const double blocksPerSec =
          wallMs > 0.0 ? (double)s_perf_blocks_total * 1000.0 / wallMs : 0.0;
      const double stepMs = wallMs / (double)s_perf_steps;
      std::fprintf(stderr,
                   "[perf] steps=%llu wallMs=%.1f stepMs=%.1f blocks=%llu "
                   "blocksPerSec=%.0f presents=%llu\n",
                   (unsigned long long)s_perf_steps, wallMs, stepMs,
                   (unsigned long long)s_perf_blocks_total, blocksPerSec,
                   (unsigned long long)aurora_present_count());
      s_perf_steps = 0;
      s_perf_blocks_total = 0;
      s_perf_t0 = std::chrono::steady_clock::now();
    }
  }
}

void ballpad_ios_host_step_frame(void) { step_guest(); }

void ballpad_ios_host_set_paused(bool paused) { g_paused.store(paused); }

// B1: UI-thread work that must not run on the guest worker (the SDL window
// attach touches UIKit scene/layer state). Called by the SwiftUI display timer
// on the main thread.
void ballpad_ios_host_pump_ui(void) {
  if (g_sdl_window != nullptr)
    ballpad_ios_host_attach_sdl_view(g_sdl_window);
}

void guest_loop() {
  // Adaptive block budget: nudge g_frame_blocks toward a ~16.6 ms step slice.
  constexpr unsigned long long kMinBlocks = 100000ull;
  constexpr unsigned long long kMaxBlocksStep = 4000000ull;
  while (!g_stop.load()) {
    if (g_paused.load()) {
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
      continue;
    }
    const auto step_t0 = std::chrono::steady_clock::now();
    step_guest();
    const double stepMs = std::chrono::duration<double, std::milli>(
                              std::chrono::steady_clock::now() - step_t0)
                              .count();
    if (stepMs < 13.0 && g_frame_blocks < kMaxBlocksStep)
      g_frame_blocks += 50000ull;
    else if (stepMs > 22.0 && g_frame_blocks > kMinBlocks)
      g_frame_blocks -= 50000ull;
  }
}

void ballpad_ios_host_stop(void) {
  g_stop = true;
  if (g_guest_thread.joinable()) {
    g_guest_thread.join();
    g_guest_thread = std::thread();
  }
  if (g_aurora_up) {
    dol_aurora_flush_gap_report();
    dol_aurora_shutdown();
    g_aurora_up = false;
  }
  g_started = false;
  g_cpu_valid = false;
}

// B1: the guest worker thread fills the EFB backing while the SwiftUI display
// timer reads it; guard the copy with a shared lock (also used by the aurora
// readback fill hook in mmio.c).
extern "C" void ballpad_ios_host_frame_lock(void) { g_frame_mutex.lock(); }
extern "C" void ballpad_ios_host_frame_unlock(void) { g_frame_mutex.unlock(); }

bool ballpad_ios_host_running(void) { return g_started.load(); }

int ballpad_ios_host_get_efb_scale(void) { return g_efb_scale; }

// Rolling present-rate helper for the SwiftUI FPS overlay.
double ballpad_ios_host_fps(void) {
  static unsigned long long s_last = 0;
  static auto s_t0 = std::chrono::steady_clock::now();
  const auto now = std::chrono::steady_clock::now();
  const double secs =
      std::chrono::duration<double>(now - s_t0).count();
  const unsigned long long cur = aurora_present_count();
  const double fps = secs > 0.0 ? (double)(cur - s_last) / secs : 0.0;
  s_last = cur;
  s_t0 = now;
  return fps;
}

void ballpad_ios_host_set_efb_scale(int scale) {
  if (scale < 1) scale = 1;
  if (scale > 4) scale = 4;
  g_efb_scale = scale;
  char buf[16];
  snprintf(buf, sizeof buf, "%d", scale);
  setenv("BALLPAD_EFB_SCALE", buf, 1);
  aurora_set_efb_scale((uint32_t)scale);
}

const char* ballpad_ios_host_card_path(void) { return g_card_path; }

// M11: copy the active memory-card container to `dest_path` (export).
bool ballpad_ios_host_export_card(const char* dest_path) {
  if (g_card_path == nullptr || g_card_path[0] == '\0' ||
      dest_path == nullptr || dest_path[0] == '\0')
    return false;
  FILE* src = fopen(g_card_path, "rb");
  if (src == nullptr)
    return false;
  FILE* dst = fopen(dest_path, "wb");
  if (dst == nullptr) {
    fclose(src);
    return false;
  }
  char buf[65536];
  size_t n = 0;
  bool ok = true;
  while ((n = fread(buf, 1, sizeof buf, src)) > 0u) {
    if (fwrite(buf, 1, n, dst) != n) {
      ok = false;
      break;
    }
  }
  fclose(src);
  fclose(dst);
  return ok;
}

// M11: copy `src_path` over the active card and re-open it (import).
bool ballpad_ios_host_import_card(const char* src_path) {
  if (g_card_path == nullptr || g_card_path[0] == '\0' ||
      src_path == nullptr || src_path[0] == '\0')
    return false;
  FILE* src = fopen(src_path, "rb");
  if (src == nullptr)
    return false;
  FILE* dst = fopen(g_card_path, "wb");
  if (dst == nullptr) {
    fclose(src);
    return false;
  }
  char buf[65536];
  size_t n = 0;
  bool ok = true;
  while ((n = fread(buf, 1, sizeof buf, src)) > 0u) {
    if (fwrite(buf, 1, n, dst) != n) {
      ok = false;
      break;
    }
  }
  fclose(src);
  fclose(dst);
  if (!ok)
    return false;
  // Re-open so the guest sees the imported card.
  if (!hle_card_open(g_card_path)) {
    std::fprintf(stderr, "[card] import re-open failed for %s\n", g_card_path);
    return false;
  }
  return true;
}

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

// Monotonic frame version (EFB fill count). The SwiftUI display path uses
// this to skip re-copying + re-rendering the CGImage when the guest has not
// produced a new frame (slow scenes would otherwise burn main-thread CPU the
// guest loop needs at 60 Hz even when the game is at 15 fps).
uint64_t ballpad_ios_host_frame_version(void) {
  if (!g_started.load())
    return 0;
  DolEfbAccess* efb = mmio_efb();
  if (efb == nullptr)
    return 0;
  return (uint64_t)efb->fill_count;
}

bool ballpad_ios_host_take_frame(uint8_t* rgba_out, uint32_t* w, uint32_t* h) {
  if (!g_started.load() || rgba_out == nullptr || w == nullptr || h == nullptr)
    return false;
  // Read the latest present-source RGBA8 frame from the software EFB backing
  // filled by the aurora readback hook (mmio_attach_efb_readback).
  DolEfbAccess* efb = mmio_efb();
  // Per-fill log is BALLPAD_DEBUG_EFB-gated (was unconditional noise; each
  // fill is one unbuffered write to the log file).
  if (getenv("BALLPAD_DEBUG_EFB") != nullptr) {
    static unsigned long long s_last_fill = 0;
    if (efb->fill_count != s_last_fill) {
      s_last_fill = efb->fill_count;
      std::fprintf(stderr, "[ballpad-ios] efb fill=%llu %ux%u color=%p\n",
                   (unsigned long long)efb->fill_count, efb->width, efb->height,
                   (void*)efb->color);
    }
  }
  if (efb == nullptr || efb->color == nullptr || efb->fill_count == 0u)
    return false;
  // Poke test (BALLPAD_EFB_POKE=1): once, at fill 58, write known bright pixels
  // into the present-source texture and dump the readback immediately plus at
  // 60/62 so we can see whether the poke survives (readback OK) or gets
  // overwritten by the scene (scene renders, dark) or never appears (readback
  // broken).
  static bool s_poked = false;
  const bool poke_mode = getenv("BALLPAD_EFB_POKE") != nullptr;
  if (poke_mode && !s_poked && efb->fill_count >= 58u) {
    s_poked = true;
    dol_aurora_poke_color(10, 10, 0xFFFF0000);     // red, viewport top-left
    dol_aurora_poke_color(320, 224, 0xFF0000FF);   // blue, viewport center
    dol_aurora_poke_color(630, 518, 0xFF00FF00);   // green, bottom-right
    dol_aurora_poke_color(320, 500, 0xFFFFFFFF);   // white, letterbox strip
    std::fprintf(stderr, "[ballpad-ios] poked 4 px at fill=%llu\n",
                 (unsigned long long)efb->fill_count);
  }
  if (poke_mode && efb->fill_count >= 58u && efb->fill_count <= 62u) {
    char path[256];
    snprintf(path, sizeof(path),
             "/Users/chrissotraidis/GitHub/ballpad/work/tmp/ios_poke_%llu.rgba",
             (unsigned long long)efb->fill_count);
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
      std::fprintf(stderr, "[ballpad-ios] poke dump %s fill=%llu\n", path,
                   (unsigned long long)efb->fill_count);
    }
  }
  const u32 fw = efb->width;
  const u32 fh = efb->height;
  if (fw == 0u || fh == 0u)
    return false;
  // B1: the guest worker fills this buffer concurrently; snapshot it under the
  // shared frame lock so a torn frame is never displayed.
  ballpad_ios_host_frame_lock();
  // Copy ARGB -> RGBA tightly packed.
  for (u32 i = 0; i < fw * fh; ++i) {
    const u32 argb = efb->color[i];
    rgba_out[i * 4u + 0u] = (uint8_t)(argb >> 16);
    rgba_out[i * 4u + 1u] = (uint8_t)(argb >> 8);
    rgba_out[i * 4u + 2u] = (uint8_t)(argb);
    rgba_out[i * 4u + 3u] = 0xFF;  // opaque: the EFB alpha channel is unused
  }
  ballpad_ios_host_frame_unlock();
  *w = fw;
  *h = fh;
  return true;
}

// B2: double-buffered RGBA staging so the SwiftUI display can hand the buffer
// straight to a CGDataProvider (no per-frame array alloc or Data copy).
namespace {
std::vector<uint8_t> g_display_buffers[2];
int g_display_buffer_index = 0;
} // namespace

const uint8_t* ballpad_ios_host_frame_ptr(uint32_t* width_out,
                                          uint32_t* height_out) {
  if (!g_started.load() || width_out == nullptr || height_out == nullptr)
    return nullptr;
  DolEfbAccess* efb = mmio_efb();
  if (efb == nullptr || efb->color == nullptr || efb->fill_count == 0u ||
      efb->width == 0u || efb->height == 0u)
    return nullptr;
  const u32 fw = efb->width;
  const u32 fh = efb->height;
  std::vector<uint8_t>& dst = g_display_buffers[g_display_buffer_index];
  const size_t bytes = (size_t)fw * fh * 4u;
  if (dst.size() != bytes)
    dst.resize(bytes);
  ballpad_ios_host_frame_lock();
  for (u32 i = 0; i < fw * fh; ++i) {
    const u32 argb = efb->color[i];
    dst[i * 4u + 0u] = (uint8_t)(argb >> 16);
    dst[i * 4u + 1u] = (uint8_t)(argb >> 8);
    dst[i * 4u + 2u] = (uint8_t)(argb);
    dst[i * 4u + 3u] = 0xFF;
  }
  ballpad_ios_host_frame_unlock();
  g_display_buffer_index ^= 1;
  *width_out = fw;
  *height_out = fh;
  return dst.data();
}

/* marker file_scope attach decl */
