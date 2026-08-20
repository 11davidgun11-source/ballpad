#pragma once
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* iOS host bridge: boots the G4QE01 guest with the Path S host and presents
 * inside the SwiftUI app's scene. SDL3 attaches its Metal view to the scene's
 * UIWindow; callers re-parent that view into their hierarchy.
 *
 * The guest run loop runs on a dedicated thread; frame presentation is paced
 * by Aurora (vsync). Touch input flows through ballpad_pad_set(0, ...).
 */

typedef struct BallpadIosHostConfig {
    const char* iso_path;          /* full path to the disc image (app sandbox) */
    const char* dol_path;          /* full path to main.dol */
    const char* card_path;         /* optional .dolcard path; NULL disables card */
    bool enable_audio;             /* 1 = open SDL audio stream */
    bool verbose;                  /* extra logging */
} BallpadIosHostConfig;

/* Boot the guest. Returns true once the run loop thread started. */
bool ballpad_ios_host_start(const BallpadIosHostConfig* cfg);

/* Stop the guest and shut down Aurora. */
void ballpad_ios_host_stop(void);

/* Step one frame of guest work on the main thread (call from a Timer/display
 * link). Drives interrupt polling, guest dispatch, and Aurora present. */
void ballpad_ios_host_step_frame(void);

/* True while the run loop is alive. */
bool ballpad_ios_host_running(void);

/* B1: pause/resume the guest worker thread (the in-game ⋯ menu pauses the
 * guest by stopping the worker, not by halting the display timer). */
void ballpad_ios_host_set_paused(bool paused);
/* B1: main-thread UI work (the SDL window attach). Call from the display
 * timer; must not run on the guest worker thread. */
void ballpad_ios_host_pump_ui(void);

/* Set the app's UIWindowScene so SDL can attach its window. Must be called on
 * the main thread before start. Accepts (UIWindowScene*) as void*. */
void ballpad_ios_host_set_window_scene(void* uiWindowScene);

/* After start, returns the SDL window's UIWindow (for re-parenting) as void*. */
void* ballpad_ios_host_sdl_uikit_window(void);

/* Host container UIView* (SwiftUI's SDLGameContainer). The bridge uses its
 * UIWindow to keep the SwiftUI scene key while the hidden SDL window provides
 * Metal bootstrap only; visible frames arrive through EFB readback. */
void ballpad_ios_host_set_container_view(void* uiView);
/* Keep SDL's auxiliary window hidden after it has initialized. Call each frame. */
void ballpad_ios_host_attach_sdl_view(void* sdlWindowPtr);

/* Host lifecycle hooks called from SwiftUI on the main thread. */
void ballpad_ios_host_application_did_become_active(void);
void ballpad_ios_host_application_will_resign_active(void);

/* Pending EFB RGBA8 frame (from present-source readback). Returns false when no
 * frame is available. */
bool ballpad_ios_host_take_frame(uint8_t* rgba_out, uint32_t* width_out,
                                 uint32_t* height_out);

/* B2: frame handoff for Core Graphics. Copies the latest frame into a leased
 * native-ARGB staging buffer and returns its pointer plus an opaque lease.
 * The caller must call release_display_frame(lease) only after Core Graphics
 * has finished with the pointer (normally from CGDataProvider's release
 * callback). If every staging buffer is still in use, this returns NULL: drop
 * the frame instead of overwriting memory held by an older CGImage. */
const uint8_t* ballpad_ios_host_take_display_frame(uint32_t* width_out,
                                                   uint32_t* height_out,
                                                   void** lease_out);
void ballpad_ios_host_release_display_frame(void* lease);

/* Current EFB frame size; false when no frame has been presented yet. */
bool ballpad_ios_host_frame_size(uint32_t* width_out, uint32_t* height_out);
/* Monotonic frame version (EFB fill count); unchanged when no new frame. */
uint64_t ballpad_ios_host_frame_version(void);

/* EFB supersample scale (M10 resolution). 1x = 640x528 baseline; 2x/3x/4x
 * recreate the EFB render target + readback at the scaled size (re-applied on
 * the next surface refresh). Call any time after init. */
int  ballpad_ios_host_get_efb_scale(void);
void ballpad_ios_host_set_efb_scale(int scale);
/* Rolling present rate (fps) for the debug overlay. */
double ballpad_ios_host_fps(void);

/* Writes a compact, privacy-safe runtime health snapshot into `buffer` for
 * user-shared diagnostics. It intentionally reports no filesystem paths, game
 * data, save data, or controller identifiers. Returns false when the buffer
 * cannot receive a complete snapshot. */
bool ballpad_ios_host_diagnostic_snapshot(char* buffer, uint32_t buffer_size);

/* M11 memory card. The active card lives at Documents/Saves/CardA.dolcard. */
const char* ballpad_ios_host_card_path(void);
bool ballpad_ios_host_export_card(const char* dest_path);
bool ballpad_ios_host_import_card(const char* src_path);

/* A1 quick-boot savestate. Capture snapshots the running match (CPU state +
 * guest RAM + ARAM + runtime device state) to Documents/QuickBoot.bss so a
 * cold launch can restore straight into the match. Returns true when the file
 * was written. Restore is automatic at start() when the file exists; set
 * BALLPAD_NO_QUICKBOOT=1 to force a full boot (e.g. to capture a fresh
 * savestate). */
bool ballpad_ios_host_save_quickboot(void);
/* True when this session resumed from the quick-boot savestate. */
bool ballpad_ios_host_quickbooted(void);

/* A2 in-app game import. game_files_present() is true when the sandbox
 * Documents holds both game.iso and main.dol (the boot paths the host uses).
 * import_game(iso_path) copies a user-picked disc image into Documents and
 * extracts sys/main.dol from it (GameCube disc header + DOL section table),
 * so a fresh install can get a game without CLI-copying files. */
bool ballpad_ios_host_game_files_present(void);
bool ballpad_ios_host_import_game(const char* iso_path);

/* A3 test hook: guest progress for the XCUITest touch-match driver. The guest
 * advances a platform-independent block count (g_blocks); the test drives the
 * real overlay at the same block anchors the autostart uses, so it works on
 * any simulator regardless of wall-clock throughput. game_state() returns the
 * guest cGame state (4 = in-match, -1 = no game). */
unsigned long long ballpad_ios_host_guest_blocks(void);
long long ballpad_ios_host_game_state(void);
int ballpad_ios_host_scene_id(void);
uint64_t ballpad_ios_host_scene_relative_fixed_updates(void);
uint64_t ballpad_ios_host_scene_seen_mask(void);

#ifdef __cplusplus
}
#endif
