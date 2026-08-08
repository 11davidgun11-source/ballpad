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

/* Set the app's UIWindowScene so SDL can attach its window. Must be called on
 * the main thread before start. Accepts (UIWindowScene*) as void*. */
void ballpad_ios_host_set_window_scene(void* uiWindowScene);

/* After start, returns the SDL window's UIWindow (for re-parenting) as void*. */
void* ballpad_ios_host_sdl_uikit_window(void);

/* Host container UIView* (SwiftUI's SDLGameContainer). The bridge re-parents
 * SDL's Metal view into it once the window exists. Main thread only. */
void ballpad_ios_host_set_container_view(void* uiView);
/* Re-parent SDL's window root view into the container. Call each frame. */
void ballpad_ios_host_attach_sdl_view(void* sdlWindowPtr);

/* Host lifecycle hooks called from SwiftUI on the main thread. */
void ballpad_ios_host_application_did_become_active(void);
void ballpad_ios_host_application_will_resign_active(void);

/* Pending EFB RGBA8 frame (from present-source readback). Returns false when no
 * frame is available. */
bool ballpad_ios_host_take_frame(uint8_t* rgba_out, uint32_t* width_out,
                                 uint32_t* height_out);

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

/* M11 memory card. The active card lives at Documents/Saves/CardA.dolcard. */
const char* ballpad_ios_host_card_path(void);
bool ballpad_ios_host_export_card(const char* dest_path);
bool ballpad_ios_host_import_card(const char* src_path);

#ifdef __cplusplus
}
#endif
