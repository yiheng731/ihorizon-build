#ifndef HORIZON_IOS_SHELL_H
#define HORIZON_IOS_SHELL_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Touch phases, mirrored from UITouch.Phase.
typedef enum {
    HZ_TOUCH_BEGAN = 0,
    HZ_TOUCH_MOVED = 1,
    HZ_TOUCH_ENDED = 2,
    HZ_TOUCH_CANCELLED = 3,
} hz_touch_phase;

// Creates the renderer on a CAMetalLayer. `layer` is a borrowed CFTypeRef:
// Swift passes Unmanaged.passUnretained(layer).toOpaque(); the layer must
// outlive the shell (it does: it owns the view).
// Returns an opaque handle, or NULL on failure (reason is printed to stderr).
void *hz_create(void *layer, uint32_t width, uint32_t height, float scale);

void hz_destroy(void *shell);

// Resizes the drawable. width/height are in pixels (points * scale).
void hz_resize(void *shell, uint32_t width, uint32_t height);

// Advances and presents one frame. dt is seconds since the previous frame.
void hz_frame(void *shell, float dt);

// Forwards one touch. x/y are in pixels, origin top-left, already scaled.
void hz_touch(void *shell, uint32_t id, uint32_t phase, float x, float y);

// Points the game at the extracted asset root (…/horizon). Call once, before
// the first hz_frame. Returns true when assets/ and data/ are both present.
bool hz_set_assets_root(const char *utf8_path);

// 0 = ready, 1 = root missing, 2 = assets/ missing, 3 = data/ missing.
int32_t hz_assets_state(const char *utf8_path);

// Which adapter wgpu picked, e.g. "Apple M2 / Metal". Borrowed, do not free.
const char *hz_adapter_info(void *shell);

// Number of frames presented since hz_create. Cheap FPS sanity check from Swift.
uint64_t hz_frame_count(void *shell);

// Last error string ("" when none). Borrowed, valid until the next call.
const char *hz_last_error(void);

#ifdef __cplusplus
}
#endif

#endif // HORIZON_IOS_SHELL_H
