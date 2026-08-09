// D2: forensic/debug tooling for the iOS host, extracted out of
// ballpad_ios_host.cpp. All of it is env-gated and off in shipped runs.
// Call sites are the per-step hook in step_guest() and the frame-read path.
#include "ballpad_debug.h"

extern "C" {
#include "generated.h"
#include "gxruntime/aurora_backend.h"
#include "gxruntime/efb_access.h"
#include "host/mmio.h"
}

#include <cstdio>
#include <cstring>
#include <cstdlib>

extern "C" void ballpad_window_probe(void);
extern "C" unsigned long long g_dec_deliveries;

void ballpad_debug_step(CPUState* cpu, unsigned long long blocks) {
  // The per-block debug gate used to call getenv() on every guest block
  // (an unfair-lock + linear environ scan that consumed ~90% of the main-thread
  // CPU); hoist it once per process.
  static const bool s_debug_threads =
      getenv("BALLPAD_DEBUG_THREADS") != nullptr;

  // Task-run counters: which game task Runners actually execute (the pad
  // update path was suspected stuck). The entry pc is only visible before the
  // dispatch consumes it, so this samples pc at step boundaries (approximate
  // for diagnostic purposes).
  if (s_debug_threads) {
    static unsigned long long s_tasks[4] = {0, 0, 0, 0};
    static unsigned long long s_padcalls[2] = {0, 0};
    const u32 pc = cpu->pc;
    if (pc == 0x801D2914u) s_tasks[0]++;       // nlTaskManager::RunAllTasks
    else if (pc == 0x8016E330u) s_tasks[1]++;  // FixedUpdateTask::Run
    else if (pc == 0x8017071Cu) s_tasks[2]++;  // FrontEndTask::Run
    else if (pc == 0x80170BACu) s_tasks[3]++;  // GameRenderTask::Run
    if (pc == 0x801C3A78u) s_padcalls[0]++;    // UpdatePlatPad
    else if (pc == 0x801C3808u) s_padcalls[1]++;  // PadStatus::Update
    if (pc == 0x8016E330u) {  // FixedUpdateTask::Run: sample per-frame ticker delta
      static u64 s_prev_tb = 0;
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
    if (blocks >= s_task_log_at) {
      s_task_log_at += 500000000ull;
      std::fprintf(stderr, "[tasks] b=%llu runAll=%llu fixed=%llu frontEnd=%llu gameRender=%llu updPlat=%llu padUpdate=%llu\n",
                   (unsigned long long)blocks, s_tasks[0], s_tasks[1], s_tasks[2], s_tasks[3],
                   s_padcalls[0], s_padcalls[1]);
    }
  }

  // 1M-block progress log.
  static unsigned long long s_next_block_log = 1000000ull;
  if (blocks >= s_next_block_log) {
    s_next_block_log += 1000000ull;
    std::fprintf(stderr, "[ballpad-ios] blocks=%llu pc=0x%08X msr=0x%08X dec=%u\n",
                 (unsigned long long)blocks, cpu->pc, cpu->msr, cpu->spr[22]);
  }

  // load-pc sampler during the match-load zone (BALLPAD_DEBUG_THREADS).
  if (blocks >= 5500000000ull && s_debug_threads &&
      cpu->pc != 0x80259294u && cpu->pc != 0x8025929Cu &&
      cpu->pc != 0x80259298u && cpu->pc != 0x802592A0u) {
    std::fprintf(stderr, "[loadpc] b=%llu pc=0x%08X\n",
                 (unsigned long long)blocks, cpu->pc);
  }

  // SDL window probe (log itself env-gated, BALLPAD_WINDOW_PROBE).
  static unsigned long long s_next_window_probe = 2500000ull;
  if (blocks >= s_next_window_probe) {
    s_next_window_probe += 2500000ull;
    ballpad_window_probe();
  }

  // Debug: dump guest OS thread states during the match-load zone to find what
  // the loading threads wait on (BALLPAD_DEBUG_THREADS=1).
  if (s_debug_threads && blocks >= 2500000000ull &&
      (blocks % 200000000ull) < 1000000ull) {
    // Save a screen-history snapshot every 400M blocks for offline review.
    if ((blocks % 400000000ull) == 0u) {
      DolEfbAccess* efb = mmio_efb();
      if (efb != nullptr && efb->color != nullptr && efb->fill_count > 0u) {
        char path[128];
        std::snprintf(path, sizeof path,
                      "/Users/chrissotraidis/GitHub/ballpad/work/tmp/snap_%llu.rgba",
                      (unsigned long long)blocks);
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
    if (blocks - s_last_dump_blocks >= 200000000ull) {
      s_last_dump_blocks = blocks;
      const u32 first = 0x80348230u;  // DefaultThread (OSThread)
      u32 t = first;
      std::fprintf(stderr, "[threads] dump at blocks=%llu rqbits@747a8=%08X @747b8=%08X\n",
                   (unsigned long long)blocks,
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
}

void ballpad_debug_efb_fill(DolEfbAccess* efb) {
  if (efb == nullptr)
    return;
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
}
