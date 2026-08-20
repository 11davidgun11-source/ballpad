// iOS host bridge (main-thread guest loop).
// SDL3/UIKit require UI on the main thread, so this host boots the guest on the
// main thread and steps frames via ballpad_ios_host_step_frame() driven by a
// SwiftUI timer/display link. Each step runs ~DEFAULT_FRAME_BLOCKS guest blocks
// then presents via Aurora (vsync-paced).
#include "ballpad_ios_host.h"
#include "ballpad_debug.h"
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
#include "host/game_map.h"
#include "host/audio.h"
}

#include <SDL3/SDL_init.h>
#include <SDL3/SDL_video.h>

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <cstdlib>
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
std::atomic<bool> g_lifecycle_paused{false};
std::atomic<unsigned long long> g_public_blocks{0};
std::atomic<long long> g_public_game_state{-1};
std::atomic<uint64_t> g_public_scene_seen_mask{0};
std::atomic<unsigned long long> g_public_step_budget{0};
std::atomic<unsigned long long> g_public_step_micros{0};
std::atomic<unsigned long long> g_display_frames_copied{0};
std::atomic<unsigned long long> g_display_frames_dropped{0};
std::atomic<unsigned long long> g_display_copy_micros{0};
std::thread g_guest_thread;
std::mutex g_frame_mutex;
std::once_flag g_process_exit_once;

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

void log_renderer_diagnostics(const char* phase) {
  DolAuroraRendererDiagnostics d{};
  if (!dol_aurora_renderer_diagnostics(&d)) {
    std::fprintf(stderr, "[quickboot-gx] phase=%s unavailable\n", phase);
    return;
  }
  std::fprintf(
      stderr,
      "[quickboot-gx] phase=%s presents=%llu fifo=%llu init=%u frame=%u "
      "boundTex=%u loadedTex=%u tluts=%u arrays=%u copyTex=%u "
      "pendingTex=%u pendingTlut=%u\n",
      phase, (unsigned long long)d.presents,
      (unsigned long long)d.fifo_bytes_current_frame, d.initialized,
      d.frame_open, d.bound_textures, d.loaded_textures, d.loaded_tluts,
      d.vertex_arrays, d.copy_textures, d.pending_textures, d.pending_tluts);
}

// UIKit does not provide a dependable termination callback, and Simulator
// destruction can call exit() after SDL/Metal services have already started
// disappearing.  The remaining native worker destructors are then unsafe and
// can abort while locking their torn-down queues.  This handler is registered
// only after the game runtime has started (so it runs before static
// destructors) and lets the OS reclaim the dying process directly.  Normal
// view teardown continues to use ballpad_ios_host_stop().
void process_exit_guard() {
  g_stop.store(true);
  std::fflush(stderr);
  _Exit(EXIT_SUCCESS);
}
} // namespace

// ---- A1 quick-boot savestate (resume a match on cold launch) ----
namespace {
constexpr char kQuickbootMagic[4] = {'B', 'P', 'S', 'V'};
// Version 5 adds the compact guest-addressed HLE GX binding table. It permits
// a diagnostic restore to re-emit pointer-bearing textures/TLUTs/arrays after
// hle_install resets them; native Aurora/WGPU state remains deliberately
// unsaved. Earlier snapshots cannot provide this semantic binding state.
// Version 4 invalidates snapshots captured before the gxcore indexed-array
// binding restore and Aurora frame-ownership fixes. Their byte layout still
// matches v3, but their renderer state is not semantically compatible: static
// stadium geometry survives while skinned player meshes collapse. Never
// silently accept one of those snapshots as a valid fast boot.
constexpr uint32_t kQuickbootVersion = 5;
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
  // Added without changing the fixed header layout. Old snapshots store zero
  // here and remain readable (but cannot restore their missing audio DMA).
  uint32_t audio_size;
  uint32_t hle_gx_size;
};

std::string quickboot_documents_dir() {
  const char* home = getenv("HOME");
  return home != nullptr ? std::string(home) + "/Documents"
                         : std::string("Documents");
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
  log_renderer_diagnostics("save");
  const uint32_t cpuRegsSize = (uint32_t)offsetof(CPUState, external_read);
  const uint32_t cpuTailSize =
      (uint32_t)(sizeof(CPUState) - offsetof(CPUState, ram));
  const uint32_t ramSize = cpu->ram_size;
  const uint32_t aramSize = ARAM_SIZE;
  const uint32_t interruptSize = interrupt_save_state_size();
  const uint32_t mmioSize = mmio_save_state_size();
  const uint32_t audioSize = audio_save_state_size();
  const uint32_t hleGxSize = hle_gx_quickboot_state_size();
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
  h.audio_size = audioSize;
  h.hle_gx_size = hleGxSize;
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
  std::vector<uint8_t> ab(audioSize);
  audio_save_state(ab.data());
  ok = ok && fwrite(ab.data(), 1, audioSize, f) == audioSize;
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
  std::vector<uint8_t> hb(hleGxSize);
  if (hleGxSize != 0u)
    ok = ok && hle_gx_quickboot_save(hb.data(), hleGxSize) &&
               fwrite(hb.data(), 1, hleGxSize, f) == hleGxSize;
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
               "[quickboot] saved %s (%u+%u+%u+%u+%u+%u+%u+%u+%u+%u bytes, "
               "%llu blocks) "
               "in %.1f ms\n",
               path.c_str(), (unsigned)cpuRegsSize, (unsigned)cpuTailSize,
               (unsigned)ramSize, (unsigned)aramSize, (unsigned)interruptSize,
               (unsigned)mmioSize, (unsigned)audioSize, (unsigned)frontendSize,
               (unsigned)gxcoreSize, (unsigned)hleGxSize,
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
  struct stat imageStat;
  const bool imageStatOK = fstat(fileno(in), &imageStat) == 0;
  if (!imageStatOK || imageStat.st_size != 1459978240ll) {
    std::fprintf(stderr, "[import] unsupported image size: %lld\n",
                 (long long)(imageStatOK ? imageStat.st_size : -1));
    fclose(in);
    return false;
  }
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
  static const uint8_t kGameCode[6] = {'G', '4', 'Q', 'E', '0', '1'};
  static const uint8_t kDiscMagic[4] = {0xC2, 0x33, 0x9F, 0x3D};
  if (ok && (memcmp(discHeader, kGameCode, sizeof kGameCode) != 0 ||
             discHeader[6] != 0 || discHeader[7] != 0 ||
             memcmp(discHeader + 0x1Cu, kDiscMagic, sizeof kDiscMagic) != 0)) {
    std::fprintf(stderr, "[import] unsupported disc (expected G4QE01 rev 0)\n");
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
  // Activate both files transactionally. A failed second rename must not
  // leave a new image paired with the previous main.dol (or vice versa).
  const std::string isoBackup = isoDest + ".previous";
  const std::string dolBackup = dolDest + ".previous";
  remove(isoBackup.c_str());
  remove(dolBackup.c_str());
  const bool hadIso = quickboot_file_exists(isoDest.c_str());
  const bool hadDol = quickboot_file_exists(dolDest.c_str());
  bool backedUpIso = !hadIso || rename(isoDest.c_str(), isoBackup.c_str()) == 0;
  bool backedUpDol = !hadDol || rename(dolDest.c_str(), dolBackup.c_str()) == 0;
  if (!backedUpIso || !backedUpDol) {
    if (hadIso && backedUpIso) rename(isoBackup.c_str(), isoDest.c_str());
    if (hadDol && backedUpDol) rename(dolBackup.c_str(), dolDest.c_str());
    remove(isoTmp.c_str());
    remove(dolTmp.c_str());
    std::fprintf(stderr, "[import] could not stage previous game data\n");
    return false;
  }
  const bool installedDol = rename(dolTmp.c_str(), dolDest.c_str()) == 0;
  const bool installedIso = installedDol &&
                            rename(isoTmp.c_str(), isoDest.c_str()) == 0;
  if (!installedDol || !installedIso) {
    remove(isoDest.c_str());
    remove(dolDest.c_str());
    if (hadIso) rename(isoBackup.c_str(), isoDest.c_str());
    if (hadDol) rename(dolBackup.c_str(), dolDest.c_str());
    remove(isoTmp.c_str());
    remove(dolTmp.c_str());
    std::fprintf(stderr, "[import] activation failed; previous data restored\n");
    return false;
  }
  remove(isoBackup.c_str());
  remove(dolBackup.c_str());
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
  const uint32_t expectedAudioSize = audio_save_state_size();
  ok = ok && (h.audio_size == 0u || h.audio_size == expectedAudioSize);
  ok = ok && h.hle_gx_size == hle_gx_quickboot_state_size();
  std::vector<uint8_t> ab(h.audio_size);
  if (h.audio_size != 0u)
    ok = ok && fread(ab.data(), 1, h.audio_size, f) == h.audio_size;
  std::vector<uint8_t> fb(h.frontend_size);
  ok = ok && fread(fb.data(), 1, h.frontend_size, f) == h.frontend_size;
  std::vector<uint8_t> gb(h.gxcore_size);
  ok = ok && fread(gb.data(), 1, h.gxcore_size, f) == h.gxcore_size;
  std::vector<uint8_t> hb(h.hle_gx_size);
  if (h.hle_gx_size != 0u)
    ok = ok && fread(hb.data(), 1, h.hle_gx_size, f) == h.hle_gx_size;
  fclose(f);
  if (!ok)
    return false;
  aram_restore(aram.data());
  interrupt_restore_state(ib.data());
  mmio_restore_state(mb.data());
  if (h.audio_size != 0u && !audio_restore_state(ab.data(), h.audio_size))
    return false;
  // The live Aurora product renderer carries no optional shadow-frontend or
  // GXCore state. An empty blob is therefore a valid snapshot, not a failed
  // QuickBoot restore; only ask the optional subsystems to restore when this
  // image actually contains their state.
  if (h.frontend_size != 0u &&
      !dol_aurora_frontend_restore_state(fb.data(), h.frontend_size))
    return false;
  if (h.gxcore_size != 0u &&
      !dol_aurora_gxcore_restore_state(gb.data(), h.gxcore_size))
    return false;
  if (h.hle_gx_size != 0u &&
      !hle_gx_quickboot_restore(&g_cpu, hb.data(), h.hle_gx_size))
    return false;
  log_renderer_diagnostics("restore-runtime");
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
  // Keep DMA polling out of the hot path when the host has no active audio
  // output. GameHostView enables it only for explicit audio diagnostics until
  // the QuickBoot and physical-device audio gates are accepted.
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
  // dol_aurora_initialize owns the complete frame lifecycle: it opens the
  // first recording packet here and every present closes/reopens it. Opening
  // a second packet from the host overwrites Aurora's active-frame pointer
  // without updating backend ownership, leaking the first packet and leaving
  // later GX draws outside a valid recording frame.

  CPUState* cpu = &g_cpu;
  if (!cpu_init(cpu)) { return false; }
  // QuickBoot is deliberately opt-in until the live Aurora GX renderer can
  // restore all state needed by skinned player meshes and HUD display lists.
  // Its CPU/RAM/audio recovery is fast, but an incomplete graphics restore
  // produces a running match with visibly wrong gameplay. Prefer a slow,
  // correct fresh boot for normal users. BALLPAD_ENABLE_QUICKBOOT=1 enables
  // the diagnostic path; BALLPAD_NO_QUICKBOOT=1 always wins for a fresh boot.
  // The CPU/regs part restores before mmio_install so the install can re-wire
  // this session's external-memory hooks; ARAM/device blobs restore afterwards.
  bool quickboot = false;
  const bool quickbootEnabled =
      getenv("BALLPAD_ENABLE_QUICKBOOT") != nullptr &&
      getenv("BALLPAD_ENABLE_QUICKBOOT")[0] != '0' &&
      getenv("BALLPAD_NO_QUICKBOOT") == nullptr;
  if (quickbootEnabled) {
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
  } else if (quickboot_file_exists(quickboot_path().c_str())) {
    std::fprintf(stderr,
                 "[quickboot] bypassed by default: live Aurora GX graphics "
                 "state is not parity-restored; set BALLPAD_ENABLE_QUICKBOOT=1 "
                 "only for diagnostics\n");
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
  g_lifecycle_paused.store(false);
  g_public_blocks.store(g_blocks, std::memory_order_relaxed);
  g_public_game_state.store(-1, std::memory_order_relaxed);
  g_public_scene_seen_mask.store(0, std::memory_order_relaxed);
  std::call_once(g_process_exit_once,
                 [] { std::atexit(process_exit_guard); });
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
  // Scene history is a diagnostic/test hook, not gameplay state. Sampling it
  // once per guest block materially taxes the hottest loop; a 50K-block
  // cadence is comfortably below the source scene transition windows while
  // keeping the production path bounded.
  static unsigned long long s_next_scene_probe = 50000ull;
  unsigned long long until = g_blocks + g_frame_blocks;
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
    if (g_blocks >= s_next_scene_probe) {
      s_next_scene_probe += 50000ull;
      HleSceneSnapshot observed_scene{};
      hle_scene_snapshot(&observed_scene);
      const int observed_scene_id = observed_scene.requested_scene >= 0
          ? observed_scene.requested_scene : observed_scene.current_scene;
      if (observed_scene_id >= 0 && observed_scene_id < 64)
        g_public_scene_seen_mask.fetch_or(1ull << observed_scene_id,
                                          std::memory_order_relaxed);
    }
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
  // Scene-driven developer automation. It reacts to source-named scene
  // observations and relative FixedUpdateTask frames only.
  static bool s_autostart = [] {
    const char* v = getenv("BALLPAD_AUTOSTART");
    return v != nullptr && v[0] != '\0' && v[0] != '0';
  }();
  if (s_autostart && !g_quickbooted) {
    static constexpr const char* kSceneMoveSegmentId =
        "ballpad-scene-move-v1:neutral-600-fixed-updates";
    static constexpr const char* kSceneMoveSegmentSha256 =
        "1c446471cbd11091671af575f8317d60af0e7f7f6dfe5a41e4f71f186c836a46";
    struct SceneAutoDriver {
      int last_scene = -999;
      unsigned substep = 0;
      unsigned action_attempts = 0;
      unsigned sequence_attempts = 0;
      uint64_t scene_enter_frame = 0;
      uint64_t next_action_frame = 0;
      uint64_t action_start = 0;
      uint16_t button = 0;
      bool active = false;
      bool released = false;
      bool move_segment_complete = false;
      bool move_segment_advanced = false;
      bool watchdog_reported = false;
    };
    static SceneAutoDriver d;
    HleSceneSnapshot scene{};
    hle_scene_snapshot(&scene);
    const uint64_t frame = scene.relative_fixed_updates;
    const int observed = scene.requested_scene >= 0 ? scene.requested_scene : scene.current_scene;
    const bool match_zero = (scene.marker_flags & 2u) != 0u;
    if (match_zero) {
      if (!d.released) {
        d.released = true;
        d.active = false;
        ballpad_pad_clear_touch(0);
        std::fprintf(stderr, "[ballpad-ios] scene automation released at match-zero rel_frame=%llu\n",
                     (unsigned long long)frame);
        std::fprintf(stderr, "[ballpad-ios] scene move segment id=%s sha256=%s start_rel_frame=%llu input=neutral\n",
                     kSceneMoveSegmentId, kSceneMoveSegmentSha256,
                     (unsigned long long)frame);
      }
      if (d.released && !d.move_segment_complete && frame >= 600u) {
        d.move_segment_complete = true;
        std::fprintf(stderr, "[ballpad-ios] scene move segment id=%s sha256=%s complete_rel_frame=%llu\n",
                     kSceneMoveSegmentId, kSceneMoveSegmentSha256,
                     (unsigned long long)frame);
      }
      if (d.move_segment_complete && !d.move_segment_advanced && frame >= 900u) {
        d.move_segment_advanced = true;
        std::fprintf(stderr, "[ballpad-ios] scene move segment id=%s sha256=%s continue_rel_frame=%llu input=neutral\n",
                     kSceneMoveSegmentId, kSceneMoveSegmentSha256,
                     (unsigned long long)frame);
      }
    } else if (observed != d.last_scene) {
      d.last_scene = observed;
      d.substep = 0;
      d.action_attempts = 0;
      d.sequence_attempts = 0;
      d.scene_enter_frame = frame;
      d.next_action_frame = frame;
      d.active = false;
      d.button = 0;
    }
    // HealthWarningSceneV2::Update does not consult FE input until its
    // source-defined two-second presentation delay has elapsed (60 Hz fixed
    // updates). Keep this readiness debounce in relative guest frames.
    // ChooseCaptainsSceneV2's pinned update returns while its presentation is
    // still in the opening slide (the side phase explicitly gates at 1.15 s).
    // Give both source-defined presentation gates time to settle.
    const uint64_t ready_frame = d.scene_enter_frame +
        (observed == 51 ? 120u : (observed == 8 ? 90u : 0u));
    if (!match_zero && !d.active && observed == d.last_scene &&
        frame >= ready_frame && frame >= d.next_action_frame &&
        d.action_attempts < 3u) {
      uint16_t next = 0;
      if ((observed == 51 || observed == 2 || observed == 3 || observed == 9 ||
           (observed >= 31 && observed <= 34)) && d.substep == 0)
        next = BALLPAD_BUTTON_A;
      else if (observed == 35 && d.substep < 2)
        next = d.substep == 0 ? BALLPAD_BUTTON_DOWN : BALLPAD_BUTTON_A;
      else if (observed >= 4 && observed <= 7 && d.substep < 2)
        next = d.substep == 0 ? BALLPAD_BUTTON_LEFT : BALLPAD_BUTTON_A;
      // ChooseCaptainsSceneV2 first advances the captain phase, then enters
      // IChooseSide; its source-side controller path requires left-side
      // assignment before the two final acceptance presses.
      else if (observed == 8 && d.substep < 4)
        next = d.substep == 1 ? BALLPAD_BUTTON_LEFT : BALLPAD_BUTTON_A;
      else if (observed >= 0 && observed <= 65 && d.substep == 0)
        next = BALLPAD_BUTTON_A;
      if (next != 0) {
        d.button = next;
        d.action_start = frame;
        d.active = true;
        d.action_attempts++;
        std::fprintf(stderr, "[ballpad-ios] scene action scene=%d substep=%u btn=0x%04X rel_frame=%llu\n",
                     observed, d.substep, d.button, (unsigned long long)frame);
      }
    }
    if (!match_zero && d.active) {
      BallPadStatus pad{};
      pad.err = 0;
      // Menu handlers sample pad state across several fixed updates; match
      // the proven touch-driver hold without tying the action to guest blocks.
      if (frame - d.action_start < 30u) {
        pad.button = d.button;
        ballpad_pad_set(0, &pad);
      } else {
        d.active = false;
        if ((observed == 35 || (observed >= 4 && observed <= 7)) && d.substep < 2u) {
          d.substep++;
          d.action_attempts = 0;
        } else if (observed == 8 && d.substep < 4u) {
          d.substep++;
          d.action_attempts = 0;
          if (d.substep == 4u) {
            d.sequence_attempts++;
            if (d.sequence_attempts < 2u) {
              d.substep = 0;
              d.action_attempts = 0;
            }
          }
        }
        // A JustPressed consumer may sample before a scene's source-defined
        // readiness point. Permit at most two release-gap retries while the
        // named scene remains unchanged.
        d.next_action_frame = frame + 60u;
        ballpad_pad_clear_touch(0);
      }
    }
    if (!match_zero && !d.watchdog_reported && frame >= 30000u) {
      d.watchdog_reported = true;
      std::fprintf(stderr, "[ballpad-ios] scene watchdog current=%d expected=match-zero rel_frame=%llu\n",
                   observed, (unsigned long long)frame);
    }
    // A1 quick-boot: capture the savestate while the scene driver is parked
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
    const bool quickbootCaptureEnabled =
        getenv("BALLPAD_ENABLE_QUICKBOOT") != nullptr &&
        getenv("BALLPAD_ENABLE_QUICKBOOT")[0] != '0';
    if (quickbootCaptureEnabled && !s_quickboot_captured &&
        getenv("BALLPAD_SKIP_QUICKBOOT_SAVE") == nullptr &&
        scene.current_scene == 9 &&
        !d.active &&
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
  // cadence. Do not send "extra" A presses: A is tackle once the match is
  // live, so those presses can put most characters into extreme dive poses
  // and make a healthy render look like broken geometry.
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
      static const u16 kQbButtons[] = {BALLPAD_BUTTON_A};
      static const unsigned long long kQbSpacing[] = {20000000ull};
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
        if (s_qb_drive_step >= 1) {
          s_qb_drive_done = true;
          std::fprintf(stderr, "[quickboot] match-start drive complete\n");
        }
      }
      ballpad_pad_set(0, &s);
    }
  }
  if (g_quickbooted) {
    // Sample before/after the queued match-start input and again after the
    // renderer has had time to consume normal draw traffic. These snapshots
    // are evidence only; do not infer serializability from a nonzero count.
    static unsigned s_qb_renderer_samples = 0;
    static const unsigned long long kQbSampleOffsets[] = {
        0ull, 120000000ull, 1200000000ull,
    };
    static unsigned long long s_qb_restore_blocks = 0;
    if (s_qb_renderer_samples == 0u && s_qb_restore_blocks == 0u)
      s_qb_restore_blocks = g_blocks;
    while (s_qb_renderer_samples <
               sizeof(kQbSampleOffsets) / sizeof(kQbSampleOffsets[0]) &&
           g_blocks >= s_qb_restore_blocks +
                           kQbSampleOffsets[s_qb_renderer_samples]) {
      const char* const phases[] = {"restore-step", "post-input", "steady"};
      log_renderer_diagnostics(phases[s_qb_renderer_samples]);
      ++s_qb_renderer_samples;
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
  g_public_blocks.store(g_blocks, std::memory_order_relaxed);
  long long publicGameState = -1;
  const u32 publicGame = mem_read32(cpu, 0x80373708u);
  if (publicGame >= 0x80000000u)
    publicGameState = (long long)mem_read32(cpu, publicGame + 0x24u);
  g_public_game_state.store(publicGameState, std::memory_order_relaxed);
  g_public_step_budget.store(g_frame_blocks, std::memory_order_relaxed);
  const auto step_elapsed = std::chrono::steady_clock::now() - t_step_begin;
  g_public_step_micros.store(
      (unsigned long long)std::chrono::duration_cast<std::chrono::microseconds>(
          step_elapsed).count(),
      std::memory_order_relaxed);
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
  // D2: forensic tooling (task counters, block log, window probe, thread
  // dumps) lives in ballpad_debug.cpp; this one call is the only host hook.
  ballpad_debug_step(cpu, g_blocks);
}

void ballpad_ios_host_step_frame(void) { step_guest(); }

void ballpad_ios_host_set_paused(bool paused) { g_paused.store(paused); }

// B1: UI-thread work that must not run on the guest worker. Keep SDL's
// auxiliary window hidden; SwiftUI and GameController own the iOS input path,
// and the SwiftUI image view is the sole visible output.
void ballpad_ios_host_pump_ui(void) {
  if (g_sdl_window != nullptr)
    ballpad_ios_host_attach_sdl_view(g_sdl_window);
}

void guest_loop() {
  // Adaptive block budget: nudge g_frame_blocks toward a ~16.6 ms step slice.
  constexpr unsigned long long kMinBlocks = 100000ull;
  constexpr unsigned long long kMaxBlocksStep = 4000000ull;
  constexpr double kTargetStepMs = 16.6;
  constexpr double kSlowStepMs = 18.0;
  constexpr double kFastStepMs = 14.0;
  while (!g_stop.load()) {
    if (g_paused.load() || g_lifecycle_paused.load()) {
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
      continue;
    }
    const auto step_t0 = std::chrono::steady_clock::now();
    step_guest();
    const double stepMs = std::chrono::duration<double, std::milli>(
                              std::chrono::steady_clock::now() - step_t0)
                              .count();
    if (stepMs < kFastStepMs && g_frame_blocks < kMaxBlocksStep)
      g_frame_blocks += 50000ull;
    else if (stepMs > kSlowStepMs && g_frame_blocks > kMinBlocks) {
      const auto decrement = stepMs > (kTargetStepMs * 1.5) ? 150000ull : 75000ull;
      g_frame_blocks = g_frame_blocks > kMinBlocks + decrement ? g_frame_blocks - decrement : kMinBlocks;
    }
    // Keep the emulated audio clock from outrunning the host audio consumer
    // when a light scene completes early. Block adaptation controls workload;
    // this remainder keeps a fixed update tied to real time without adding
    // latency to genuinely slow scenes.
    if (stepMs < kTargetStepMs) {
      std::this_thread::sleep_for(std::chrono::duration<double, std::milli>(
          kTargetStepMs - stepMs));
    }
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
  g_public_game_state.store(-1, std::memory_order_relaxed);
  g_public_scene_seen_mask.store(0, std::memory_order_relaxed);
  g_public_step_budget.store(0, std::memory_order_relaxed);
  g_public_step_micros.store(0, std::memory_order_relaxed);
}

// B1: the guest worker thread fills the EFB backing while the SwiftUI display
// timer reads it; guard the copy with a shared lock (also used by the aurora
// readback fill hook in mmio.c).
extern "C" void ballpad_ios_host_frame_lock(void) { g_frame_mutex.lock(); }
extern "C" void ballpad_ios_host_frame_unlock(void) { g_frame_mutex.unlock(); }

bool ballpad_ios_host_running(void) { return g_started.load(); }

// A3 test hook: the guest's platform-independent block counter. The XCUITest
// touch-match driver polls this (via a test-only SwiftUI label) and presses
// the real overlay at the autostart's block anchors, so it works on any
// simulator regardless of wall-clock throughput.
unsigned long long ballpad_ios_host_guest_blocks(void) {
  return g_public_blocks.load(std::memory_order_relaxed);
}

// A3 test hook: the guest cGame state (4 = in-match). Reads the same guest
// memory the [threads] debug dump uses (g_pGame at 0x80373708, state at +0x24).
long long ballpad_ios_host_game_state(void) {
  if (!g_started.load())
    return -1;
  return g_public_game_state.load(std::memory_order_relaxed);
}

int ballpad_ios_host_scene_id(void) {
  if (!g_started.load())
    return -1;
  HleSceneSnapshot scene{};
  hle_scene_snapshot(&scene);
  return scene.requested_scene >= 0 ? scene.requested_scene : scene.current_scene;
}

uint64_t ballpad_ios_host_scene_relative_fixed_updates(void) {
  if (!g_started.load())
    return 0;
  HleSceneSnapshot scene{};
  hle_scene_snapshot(&scene);
  return scene.relative_fixed_updates;
}

uint64_t ballpad_ios_host_scene_seen_mask(void) {
  return g_public_scene_seen_mask.load(std::memory_order_relaxed);
}

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

bool ballpad_ios_host_diagnostic_snapshot(char* buffer, uint32_t buffer_size) {
  if (buffer == nullptr || buffer_size == 0u)
    return false;

  uint64_t frameVersion = 0;
  uint32_t frameWidth = 0;
  uint32_t frameHeight = 0;
  ballpad_ios_host_frame_lock();
  DolEfbAccess* efb = mmio_efb();
  if (efb != nullptr) {
    frameVersion = (uint64_t)efb->fill_count;
    frameWidth = efb->width;
    frameHeight = efb->height;
  }
  ballpad_ios_host_frame_unlock();

  HleSceneSnapshot scene{};
  hle_scene_snapshot(&scene);

  const int written = std::snprintf(
      buffer, buffer_size,
      "Host running: %s\\n"
      "Host starting: %s\\n"
      "Guest paused: %s\\n"
      "Lifecycle paused: %s\\n"
      "Boot source: %s\\n"
      "Decomp commit: %s\\n"
      "Decomp DOL SHA-1: %s\\n"
      "Decomp SDK SHA-256: %s\\n"
      "Scene sequence: %llu\\n"
      "Scene requested/current: %d/%d\\n"
      "Scene markers: 0x%08X\\n"
      "Relative fixed updates: %llu\\n"
      "Guest game state: %d\\n"
      "Guest step budget: %llu blocks\\n"
      "Last guest step: %.2f ms\\n"
      "Aurora presents: %llu\\n"
      "EFB frame version: %llu\\n"
      "EFB frame size: %ux%u\\n"
      "Display frames copied: %llu\\n"
      "Display frames dropped: %llu\\n"
      "EFB scale: %dx\\n",
      g_started.load() ? "yes" : "no",
      g_starting.load() ? "yes" : "no",
      g_paused.load() ? "yes" : "no",
      g_lifecycle_paused.load() ? "yes" : "no",
      g_quickbooted ? "QuickBoot" : "fresh boot",
      game_decomp_commit(),
      game_decomp_dol_sha1(),
      game_decomp_sdk_sha256(),
      (unsigned long long)scene.event_sequence,
      scene.requested_scene, scene.current_scene, scene.marker_flags,
      (unsigned long long)scene.relative_fixed_updates, scene.game_state,
      g_public_step_budget.load(std::memory_order_relaxed),
      (double)g_public_step_micros.load(std::memory_order_relaxed) / 1000.0,
      aurora_present_count(),
      (unsigned long long)frameVersion,
      frameWidth, frameHeight,
      g_display_frames_copied.load(std::memory_order_relaxed),
      g_display_frames_dropped.load(std::memory_order_relaxed),
      g_efb_scale);
  return written >= 0 && (uint32_t)written < buffer_size;
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

void ballpad_ios_host_application_did_become_active(void) {
  g_lifecycle_paused.store(false);
  std::fprintf(stderr, "[lifecycle] active started=%d presents=%llu\n",
               g_started.load() ? 1 : 0, aurora_present_count());
}
void ballpad_ios_host_application_will_resign_active(void) {
  g_lifecycle_paused.store(true);
  std::fprintf(stderr, "[lifecycle] inactive started=%d presents=%llu\n",
               g_started.load() ? 1 : 0, aurora_present_count());
}
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
  ballpad_ios_host_frame_lock();
  DolEfbAccess* efb = mmio_efb();
  const uint64_t version = efb != nullptr ? (uint64_t)efb->fill_count : 0;
  ballpad_ios_host_frame_unlock();
  return version;
}

bool ballpad_ios_host_take_frame(uint8_t* rgba_out, uint32_t* w, uint32_t* h) {
  if (!g_started.load() || rgba_out == nullptr || w == nullptr || h == nullptr)
    return false;
  // Read the latest present-source RGBA8 frame from the software EFB backing
  // filled by the aurora readback hook (mmio_attach_efb_readback).
  DolEfbAccess* efb = mmio_efb();
  // D2: EFB readback diagnostics (per-fill log + poke test) live in
  // ballpad_debug.cpp, env-gated off in shipped runs.
  ballpad_debug_efb_fill(efb);
  if (efb == nullptr || efb->color == nullptr || efb->fill_count == 0u)
    return false;
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

// B2: leased native-ARGB staging so SwiftUI can hand the buffer directly to a
// CGDataProvider. The image provider can outlive the next display tick, so a
// conventional two-buffer swap is not safe: Core Graphics could still read a
// buffer while the host overwrites it. A small pool retains each slot until
// the provider's release callback returns it. On little-endian Apple hardware
// the bytes are BGRA; Core Graphics receives the matching byte-order descriptor.
namespace {
struct DisplayFrameSlot {
  std::vector<uint8_t> bytes;
  bool leased = false;
};
constexpr size_t kDisplayFrameSlotCount = 3;
DisplayFrameSlot g_display_slots[kDisplayFrameSlotCount];
std::mutex g_display_slots_mutex;
} // namespace

const uint8_t* ballpad_ios_host_take_display_frame(uint32_t* width_out,
                                                   uint32_t* height_out,
                                                   void** lease_out) {
  if (!g_started.load() || width_out == nullptr || height_out == nullptr ||
      lease_out == nullptr)
    return nullptr;

  std::unique_lock<std::mutex> slots_lock(g_display_slots_mutex);
  DisplayFrameSlot* slot = nullptr;
  for (DisplayFrameSlot& candidate : g_display_slots) {
    if (!candidate.leased) {
      slot = &candidate;
      slot->leased = true;
      break;
    }
  }
  if (slot == nullptr) {
    g_display_frames_dropped.fetch_add(1, std::memory_order_relaxed);
    return nullptr;
  }

  ballpad_ios_host_frame_lock();
  DolEfbAccess* efb = mmio_efb();
  if (efb == nullptr || efb->color == nullptr || efb->fill_count == 0u ||
      efb->width == 0u || efb->height == 0u) {
    ballpad_ios_host_frame_unlock();
    slot->leased = false;
    return nullptr;
  }
  const u32 fw = efb->width;
  const u32 fh = efb->height;
  const unsigned long long fill = (unsigned long long)efb->fill_count;
  const size_t bytes = (size_t)fw * fh * sizeof(u32);
  if (slot->bytes.size() != bytes)
    slot->bytes.resize(bytes);
  const auto copy_start = std::chrono::steady_clock::now();
  std::memcpy(slot->bytes.data(), efb->color, bytes);
  const auto copy_micros = static_cast<unsigned long long>(
      std::chrono::duration_cast<std::chrono::microseconds>(
          std::chrono::steady_clock::now() - copy_start)
          .count());
  g_display_copy_micros.fetch_add(copy_micros, std::memory_order_relaxed);
  static const bool s_copy_diag = [] {
    const char* value = std::getenv("BALLPAD_DISPLAY_COPY_DIAGNOSTICS");
    return value != nullptr && value[0] == '1';
  }();
  if (s_copy_diag && (g_display_frames_copied.load(std::memory_order_relaxed) % 120u) == 0u) {
    std::fprintf(stderr, "[display-copy] fill=%llu bytes=%zu copy_us=%llu total_copy_us=%llu\n",
                 fill, bytes, copy_micros,
                 g_display_copy_micros.load(std::memory_order_relaxed));
  }

  // Opt-in forensic capture of the exact native-endian BGRA buffer handed to
  // Core Graphics. This separates a live Aurora/readback corruption from a
  // SwiftUI/CGImage presentation fault without altering the normal frame path.
  static const char* s_dump_dir = std::getenv("BALLPAD_EFB_DUMP_DIR");
  static const unsigned long long s_dump_after = [] {
    const char* value = std::getenv("BALLPAD_EFB_DUMP_AFTER_FILL");
    return value != nullptr ? std::strtoull(value, nullptr, 10) : 0ull;
  }();
  static const unsigned long long s_dump_stride = [] {
    const char* value = std::getenv("BALLPAD_EFB_DUMP_STRIDE");
    return value != nullptr ? std::max(1ull, std::strtoull(value, nullptr, 10)) : 1ull;
  }();
  static const unsigned long long s_dump_limit = [] {
    const char* value = std::getenv("BALLPAD_EFB_DUMP_LIMIT");
    return value != nullptr ? std::max(1ull, std::strtoull(value, nullptr, 10)) : 1ull;
  }();
  static unsigned long long s_dump_count = 0;
  static unsigned long long s_next_dump_fill = s_dump_after;
  if (s_dump_dir != nullptr && s_dump_dir[0] != '\0' && s_dump_count < s_dump_limit &&
      fill >= s_next_dump_fill) {
    char path[1200];
    std::snprintf(path, sizeof(path), "%s/efb_native_bgra_%llu_%ux%u.raw", s_dump_dir, fill, fw, fh);
    if (FILE* dump = std::fopen(path, "wb")) {
      std::fwrite(slot->bytes.data(), 1, bytes, dump);
      std::fclose(dump);
      std::fprintf(stderr, "[efb-dump] fill=%llu path=%s bytes=%zu\n", fill, path, bytes);
      ++s_dump_count;
      s_next_dump_fill = fill + s_dump_stride;
    }
  }
  ballpad_ios_host_frame_unlock();
  *width_out = fw;
  *height_out = fh;
  *lease_out = slot;
  g_display_frames_copied.fetch_add(1, std::memory_order_relaxed);
  return slot->bytes.data();
}

void ballpad_ios_host_release_display_frame(void* lease) {
  if (lease == nullptr)
    return;
  std::lock_guard<std::mutex> slots_lock(g_display_slots_mutex);
  for (DisplayFrameSlot& slot : g_display_slots) {
    if (&slot == lease) {
      slot.leased = false;
      return;
    }
  }
}

/* marker file_scope attach decl */
