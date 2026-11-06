/* See gbm.h: no device, no buffers. */
#include "gbm.h"

#include <errno.h>
#include <string.h>

struct gbm_device *gbm_create_device(int fd) { (void)fd; errno = ENOSYS; return NULL; }
void gbm_device_destroy(struct gbm_device *gbm) { (void)gbm; }
int gbm_device_get_fd(struct gbm_device *gbm) { (void)gbm; return -1; }

struct gbm_bo *gbm_bo_create(struct gbm_device *gbm, uint32_t w, uint32_t h, uint32_t format, uint32_t flags)
{
    (void)gbm; (void)w; (void)h; (void)format; (void)flags;
    errno = ENOSYS;
    return NULL;
}
struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm, uint32_t w, uint32_t h, uint32_t format,
                                            const uint64_t *modifiers, const unsigned int count)
{
    (void)modifiers; (void)count;
    return gbm_bo_create(gbm, w, h, format, 0);
}
struct gbm_bo *gbm_bo_create_with_modifiers2(struct gbm_device *gbm, uint32_t w, uint32_t h, uint32_t format,
                                             const uint64_t *modifiers, const unsigned int count, uint32_t flags)
{
    (void)modifiers; (void)count;
    return gbm_bo_create(gbm, w, h, format, flags);
}
struct gbm_bo *gbm_bo_import(struct gbm_device *gbm, uint32_t type, void *buffer, uint32_t flags)
{
    (void)type; (void)buffer;
    return gbm_bo_create(gbm, 0, 0, 0, flags);
}
void gbm_bo_destroy(struct gbm_bo *bo) { (void)bo; }
void *gbm_bo_map(struct gbm_bo *bo, uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t flags,
                 uint32_t *stride, void **map_data)
{
    (void)bo; (void)x; (void)y; (void)w; (void)h; (void)flags; (void)stride; (void)map_data;
    return NULL;
}
void gbm_bo_unmap(struct gbm_bo *bo, void *map_data) { (void)bo; (void)map_data; }
uint32_t gbm_bo_get_width(struct gbm_bo *bo) { (void)bo; return 0; }
uint32_t gbm_bo_get_height(struct gbm_bo *bo) { (void)bo; return 0; }
uint32_t gbm_bo_get_stride(struct gbm_bo *bo) { (void)bo; return 0; }
uint32_t gbm_bo_get_stride_for_plane(struct gbm_bo *bo, int plane) { (void)bo; (void)plane; return 0; }
uint32_t gbm_bo_get_format(struct gbm_bo *bo) { (void)bo; return 0; }
uint32_t gbm_bo_get_offset(struct gbm_bo *bo, int plane) { (void)bo; (void)plane; return 0; }
uint64_t gbm_bo_get_modifier(struct gbm_bo *bo) { (void)bo; return 0; }
int gbm_bo_get_plane_count(struct gbm_bo *bo) { (void)bo; return 0; }
int gbm_bo_get_fd(struct gbm_bo *bo) { (void)bo; return -1; }
int gbm_bo_get_fd_for_plane(struct gbm_bo *bo, int plane) { (void)bo; (void)plane; return -1; }
union gbm_bo_handle gbm_bo_get_handle(struct gbm_bo *bo) { (void)bo; union gbm_bo_handle h = { 0 }; return h; }
union gbm_bo_handle gbm_bo_get_handle_for_plane(struct gbm_bo *bo, int plane)
{
    (void)plane;
    return gbm_bo_get_handle(bo);
}
char *gbm_format_get_name(uint32_t format, struct gbm_format_name_desc *desc)
{
    for (int i = 0; i < 4; i++) desc->name[i] = (char)((format >> (8 * i)) & 0xff);
    desc->name[4] = 0;
    return desc->name;
}
