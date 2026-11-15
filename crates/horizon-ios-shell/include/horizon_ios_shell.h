#ifndef HORIZON_IOS_SHELL_H
#define HORIZON_IOS_SHELL_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    HZ_TOUCH_BEGAN = 0,
    HZ_TOUCH_MOVED = 1,
    HZ_TOUCH_ENDED = 2,
    HZ_TOUCH_CANCELLED = 3,
} hz_touch_phase;

void *hz_create(void *layer, uint32_t width, uint32_t height, float scale);

void hz_destroy(void *shell);

void hz_resize(void *shell, uint32_t width, uint32_t height);

void hz_frame(void *shell, float dt);

void hz_touch(void *shell, uint32_t id, uint32_t phase, float x, float y);

bool hz_set_assets_root(const char *utf8_path);

int32_t hz_assets_state(const char *utf8_path);

const char *hz_adapter_info(void *shell);

uint64_t hz_frame_count(void *shell);

const char *hz_last_error(void);

#ifdef __cplusplus
}
#endif

#endif 
