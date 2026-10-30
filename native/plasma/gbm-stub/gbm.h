/*
 * A stand-in for Mesa's libgbm on Android. KWin needs gbm to build (its DRM
 * backend and its dmabuf allocator), but there is no DRM render node to
 * allocate from on Android: every call fails, so KWin falls back to its other
 * allocators. Declares only what KWin uses.
 */
#ifndef DESKDROID_GBM_STUB_H
#define DESKDROID_GBM_STUB_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct gbm_device;
struct gbm_bo;

union gbm_bo_handle {
    void *ptr;
    int32_t s32;
    uint32_t u32;
    int64_t s64;
    uint64_t u64;
};

struct gbm_format_name_desc {
    char name[5];
};

enum gbm_bo_flags {
    GBM_BO_USE_SCANOUT = 1 << 0,
    GBM_BO_USE_CURSOR = 1 << 1,
    GBM_BO_USE_RENDERING = 1 << 2,
    GBM_BO_USE_WRITE = 1 << 3,
    GBM_BO_USE_LINEAR = 1 << 4,
    GBM_BO_USE_PROTECTED = 1 << 5,
    GBM_BO_USE_FRONT_RENDERING = 1 << 6,
};

enum gbm_bo_transfer_flags {
    GBM_BO_TRANSFER_READ = 1 << 0,
    GBM_BO_TRANSFER_WRITE = 1 << 1,
    GBM_BO_TRANSFER_READ_WRITE = GBM_BO_TRANSFER_READ | GBM_BO_TRANSFER_WRITE,
};

#define GBM_BO_IMPORT_FD 0x5503
#define GBM_BO_IMPORT_FD_MODIFIER 0x5504
#define GBM_BO_FIXED_COMPRESSION_DEFAULT 0
/* Present in Mesa's header; KWin checks for them with #ifdef. */
#define GBM_BO_GET_FD_FOR_PLANE 1
#define GBM_KHR 1

struct gbm_device *gbm_create_device(int fd);
void gbm_device_destroy(struct gbm_device *gbm);
int gbm_device_get_fd(struct gbm_device *gbm);

struct gbm_bo *gbm_bo_create(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format, uint32_t flags);
struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format,
                                            const uint64_t *modifiers, const unsigned int count);
struct gbm_bo *gbm_bo_create_with_modifiers2(struct gbm_device *gbm, uint32_t width, uint32_t height, uint32_t format,
                                             const uint64_t *modifiers, const unsigned int count, uint32_t flags);
struct gbm_bo *gbm_bo_import(struct gbm_device *gbm, uint32_t type, void *buffer, uint32_t flags);
void gbm_bo_destroy(struct gbm_bo *bo);
void *gbm_bo_map(struct gbm_bo *bo, uint32_t x, uint32_t y, uint32_t width, uint32_t height, uint32_t flags,
                 uint32_t *stride, void **map_data);
void gbm_bo_unmap(struct gbm_bo *bo, void *map_data);
uint32_t gbm_bo_get_width(struct gbm_bo *bo);
uint32_t gbm_bo_get_height(struct gbm_bo *bo);
uint32_t gbm_bo_get_stride(struct gbm_bo *bo);
uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane);
uint32_t gbm_bo_get_format(struct gbm_bo *bo);
uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane);
uint64_t gbm_bo_get_modifier(struct gbm_bo *bo);
int gbm_bo_get_plane_count(struct gbm_bo *bo);
int gbm_bo_get_fd(struct gbm_bo *bo);
int gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int plane);
union gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo);
union gbm_bo_handle gbm_bo_get_handle_for_plane(struct gbm_bo *bo, int plane);
char *gbm_format_get_name(uint32_t gbm_format, struct gbm_format_name_desc *desc);

#ifdef __cplusplus
}
#endif

#endif
