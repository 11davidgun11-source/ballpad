/*
  BallpadProbe — the cheap half of the N2 gate.

  Why this exists: the game's own boot reads the disc, builds the front end and starts MusyX
  before it presents anything, so a Simulator dependency that is the wrong slice, or that
  quietly resolves to a host dylib, shows up as minutes of silence rather than a diagnosis.
  This probe brings up the same Aurora/SDL3/Dawn-Metal/sandbox path the game uses — the same
  entry point, the same Aurora targets, the same app bundle — asks for a presentable swapchain,
  presents a bounded number of frames and reports what it got. It never opens the disc, so
  whatever it says is about the platform layer and nothing else.

  It is a plain C translation unit on purpose: it compiles against the SDK's C compiler with no
  engine headers and no C++ runtime of its own, so a failure here cannot be blamed on the
  engine's build contract or on the port's prelude.

  Exit status is the answer: 0 when at least one frame reached the swapchain, 1 when the window
  or the drawable never arrived.
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <aurora/aurora.h>
/* Renames this file's main() to aurora_main(). Aurora's own lib/main.cpp supplies the real entry
   point, and on iOS that entry point is SDL's UIApplicationMain wrapper. */
#include <aurora/main.h>
#include <aurora/event.h>

static const char* backend_name(AuroraBackend backend)
{
    switch (backend)
    {
    case BACKEND_AUTO: return "auto";
    case BACKEND_D3D11: return "d3d11";
    case BACKEND_D3D12: return "d3d12";
    case BACKEND_METAL: return "metal";
    case BACKEND_VULKAN: return "vulkan";
    case BACKEND_OPENGL: return "opengl";
    case BACKEND_OPENGLES: return "opengles";
    case BACKEND_WEBGPU: return "webgpu";
    case BACKEND_NULL: return "null";
    default: return "unknown";
    }
}

/* A backend named on the command line wins; otherwise Metal, which is the only one iOS has.
   "null" is the escape hatch for separating "the platform layer came up" from "the GPU came
   up" when a Simulator is misbehaving. */
static AuroraBackend wanted_backend(void)
{
    const char* want = getenv("STRIKERS_BACKEND");
    if (want != NULL && strcmp(want, "null") == 0)
        return BACKEND_NULL;
    if (want != NULL && strcmp(want, "auto") == 0)
        return BACKEND_AUTO;
    return BACKEND_METAL;
}

static int env_int(const char* name, int fallback)
{
    const char* v = getenv(name);
    if (v == NULL || *v == '\0')
        return fallback;
    return atoi(v);
}

/* Aurora hands over the log buffer and its length, not a terminated string, so it is written
   with fwrite rather than fputs. */
static void probe_log(AuroraLogLevel level, const char* module, const char* message, unsigned int len)
{
    static const char* const kLevels[] = { "debug", "info", "warn", "error", "fatal" };
    const char* name = ((int)level >= 0 && level <= LOG_FATAL) ? kLevels[(int)level] : "?";
    fprintf(stderr, "[aurora] %-5s %s: ", name, module != NULL ? module : "?");
    if (message != NULL && len > 0)
        fwrite(message, 1, len, stderr);
    fputc('\n', stderr);
}

/* The sandbox is the whole reason these paths are not the desktop defaults: inside an iOS app
   HOME is the app container, SDL_GetPrefPath would be fine but is not what the game asks for,
   and neither directory exists until the app is launched. Documents and Library/Caches do
   exist, so they are where a probe that must not touch the player's card writes. */
static const char* sandbox_path(const char* override_name, const char* subdir, char* buffer, size_t size)
{
    const char* given = getenv(override_name);
    if (given != NULL && *given != '\0')
        return given;

    const char* home = getenv("HOME");
    if (home == NULL || *home == '\0')
        home = ".";
    snprintf(buffer, size, "%s/%s/", home, subdir);
    return buffer;
}

int main(int argc, char* argv[]) /* aurora_main() — see <aurora/main.h> above */
{
    char user_dir[1024];
    char cache_dir[1024];
    const char* user_path = sandbox_path("STRIKERS_USER_DIR", "Documents", user_dir, sizeof user_dir);
    const char* cache_path = sandbox_path("STRIKERS_CACHE_DIR", "Library/Caches", cache_dir, sizeof cache_dir);
    const int frames = env_int("STRIKERS_PROBE_FRAMES", 120);
    const char* capture = getenv("STRIKERS_PROBE_CAPTURE");

    AuroraConfig cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.appName = "Ballpad Probe";
    cfg.userPath = user_path;
    cfg.cachePath = cache_path;
    cfg.desiredBackend = wanted_backend();
    cfg.msaa = (uint32_t)env_int("STRIKERS_MSAA", 1);
    cfg.vsync = env_int("STRIKERS_VSYNC", 1) != 0;
    /* The port widened pointers instead of emulating the console's memory map. */
    cfg.mem1Size = 0;
    cfg.mem2Size = 0;
    cfg.windowWidth = 1334;
    cfg.windowHeight = 750;
    cfg.logCallback = probe_log;
    cfg.logLevel = LOG_INFO;

    fprintf(stderr, "[probe] start frames=%d backend=%s user=%s cache=%s\n",
            frames, backend_name(cfg.desiredBackend), user_path, cache_path);
    fflush(stderr);

    AuroraInfo info = aurora_initialize(argc, argv, &cfg);

    fprintf(stderr,
            "[probe] init backend=%s window=%s size=%ux%u fb=%ux%u native=%ux%u scale=%.3f\n",
            backend_name(info.backend), info.window != NULL ? "yes" : "no",
            info.windowSize.width, info.windowSize.height,
            info.windowSize.fb_width, info.windowSize.fb_height,
            info.windowSize.native_fb_width, info.windowSize.native_fb_height,
            (double)info.windowSize.scale);
    fflush(stderr);

    int presented = 0;
    int skipped = 0;
    int exits = 0;
    for (int frame = 0; frame < frames; frame++)
    {
        for (const AuroraEvent* ev = aurora_update(); ev != NULL && ev->type != AURORA_NONE; ++ev)
        {
            if (ev->type == AURORA_EXIT)
                exits++;
        }

        /* False means the surface is not presentable right now — minimised, or the app moved
           to the background. That is a state to report, not a frame to pretend happened. */
        if (!aurora_begin_frame())
        {
            skipped++;
            continue;
        }

        if (capture != NULL && *capture != '\0' && frame == frames - 1)
            aurora_capture_frame(capture);

        aurora_end_frame();
        presented++;

        if ((frame % 30) == 0)
        {
            fprintf(stderr, "[probe] frame %d\n", frame);
            fflush(stderr);
        }
    }

    fprintf(stderr, "[probe] %s frames=%d presented=%d skipped=%d exits=%d backend=%s\n",
            presented > 0 ? "ok" : "fail", frames, presented, skipped, exits,
            backend_name(info.backend));
    fflush(stderr);

    aurora_shutdown();

    /* SDL on iOS deliberately leaves the Cocoa run loop alive when the app's main returns, so
       an application can do its startup in main and then hand the loop over. A diagnostic that
       has to hand back an exit status to simctl does not have that option, and this is the only
       place in the port that ends the process itself. */
    exit(presented > 0 ? 0 : 1);
}
