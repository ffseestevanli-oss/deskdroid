/*
 * gpureport: prints what the phone's GPU drivers offer, for the "GPU report"
 * screen in Settings. Covers Android's OpenGL ES (EGL) and Vulkan drivers, and
 * flags the Vulkan extensions the GPU forwarding paths depend on (Venus needs
 * a way to share GPU memory with the rootfs side).
 *
 * Usage: gpureport                 system GLES and Vulkan
 *        gpureport --angle <dir>   ANGLE's GLES (libEGL_angle.so in <dir>)
 * ANGLE runs in its own process so a crash there can't hide the rest.
 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <vulkan/vulkan.h>

static const char *venus_exts[] = {
    "VK_KHR_external_memory_fd",
    "VK_EXT_external_memory_dma_buf",
    "VK_ANDROID_external_memory_android_hardware_buffer",
    "VK_EXT_image_drm_format_modifier",
    "VK_EXT_queue_family_foreign",
    "VK_KHR_external_fence_fd",
    "VK_KHR_external_semaphore_fd",
};

typedef EGLDisplay (*PFN_getDisplay)(EGLNativeDisplayType);
typedef EGLBoolean (*PFN_initialize)(EGLDisplay, EGLint *, EGLint *);
typedef const char *(*PFN_queryString)(EGLDisplay, EGLint);
typedef EGLBoolean (*PFN_chooseConfig)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *);
typedef EGLContext (*PFN_createContext)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
typedef EGLSurface (*PFN_createPbuffer)(EGLDisplay, EGLConfig, const EGLint *);
typedef EGLBoolean (*PFN_makeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
typedef EGLBoolean (*PFN_terminate)(EGLDisplay);
typedef const GLubyte *(*PFN_getString)(GLenum);

/* Loads EGL/GLES from egl_lib/gles_lib so the same code reports the system
 * driver and ANGLE. */
static void report_gles(const char *title, const char *egl_lib, const char *gles_lib)
{
    printf("== %s\n", title);
    void *egl = dlopen(egl_lib, RTLD_NOW | RTLD_LOCAL);
    void *gles = dlopen(gles_lib, RTLD_NOW | RTLD_LOCAL);
    if (!egl || !gles) {
        printf("not loadable: %s\n\n", dlerror());
        return;
    }
    PFN_getDisplay getDisplay = (PFN_getDisplay)dlsym(egl, "eglGetDisplay");
    PFN_initialize initialize = (PFN_initialize)dlsym(egl, "eglInitialize");
    PFN_queryString queryString = (PFN_queryString)dlsym(egl, "eglQueryString");
    PFN_chooseConfig chooseConfig = (PFN_chooseConfig)dlsym(egl, "eglChooseConfig");
    PFN_createContext createContext = (PFN_createContext)dlsym(egl, "eglCreateContext");
    PFN_createPbuffer createPbuffer = (PFN_createPbuffer)dlsym(egl, "eglCreatePbufferSurface");
    PFN_makeCurrent makeCurrent = (PFN_makeCurrent)dlsym(egl, "eglMakeCurrent");
    PFN_terminate terminate = (PFN_terminate)dlsym(egl, "eglTerminate");
    PFN_getString getString = (PFN_getString)dlsym(gles, "glGetString");
    if (!getDisplay || !initialize || !queryString || !chooseConfig || !createContext ||
        !createPbuffer || !makeCurrent || !terminate || !getString) {
        printf("missing EGL/GLES entry points\n\n");
        return;
    }

    EGLDisplay dpy = getDisplay(EGL_DEFAULT_DISPLAY);
    EGLint major = 0, minor = 0;
    if (dpy == EGL_NO_DISPLAY || !initialize(dpy, &major, &minor)) {
        printf("eglInitialize failed\n\n");
        return;
    }
    printf("EGL %d.%d, vendor: %s\n", major, minor, queryString(dpy, EGL_VENDOR));
    printf("EGL extensions: %s\n", queryString(dpy, EGL_EXTENSIONS));

    const EGLint cfg_attrs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, 0x40 /* EGL_OPENGL_ES3_BIT */,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_NONE,
    };
    const EGLint ctx_attrs[] = { 0x3098 /* EGL_CONTEXT_MAJOR_VERSION */, 3, EGL_NONE };
    const EGLint pb_attrs[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
    EGLConfig cfg;
    EGLint n = 0;
    if (!chooseConfig(dpy, cfg_attrs, &cfg, 1, &n) || n < 1) {
        printf("no GLES 3 pbuffer config\n\n");
        terminate(dpy);
        return;
    }
    EGLContext ctx = createContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attrs);
    EGLSurface surf = createPbuffer(dpy, cfg, pb_attrs);
    if (ctx == EGL_NO_CONTEXT || surf == EGL_NO_SURFACE || !makeCurrent(dpy, surf, surf, ctx)) {
        printf("could not create a GLES 3 context\n\n");
        terminate(dpy);
        return;
    }
    printf("GL_VENDOR: %s\n", getString(GL_VENDOR));
    printf("GL_RENDERER: %s\n", getString(GL_RENDERER));
    printf("GL_VERSION: %s\n", getString(GL_VERSION));
    printf("GL_SHADING_LANGUAGE_VERSION: %s\n", getString(GL_SHADING_LANGUAGE_VERSION));
    printf("GL_EXTENSIONS: %s\n\n", getString(GL_EXTENSIONS));
    makeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    terminate(dpy);
}

static void report_vulkan(void)
{
    printf("== Vulkan (system driver)\n");
    void *lib = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        printf("libvulkan.so not loadable: %s\n\n", dlerror());
        return;
    }
    PFN_vkGetInstanceProcAddr gipa = (PFN_vkGetInstanceProcAddr)dlsym(lib, "vkGetInstanceProcAddr");
    PFN_vkEnumerateInstanceVersion enumVersion =
        (PFN_vkEnumerateInstanceVersion)gipa(NULL, "vkEnumerateInstanceVersion");
    PFN_vkCreateInstance createInstance = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
    uint32_t loader = VK_API_VERSION_1_0;
    if (enumVersion) enumVersion(&loader);
    printf("loader: %u.%u.%u\n", VK_VERSION_MAJOR(loader), VK_VERSION_MINOR(loader), VK_VERSION_PATCH(loader));

    VkApplicationInfo app = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "gpureport",
        .apiVersion = loader >= VK_API_VERSION_1_1 ? VK_API_VERSION_1_1 : VK_API_VERSION_1_0,
    };
    VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
    VkInstance inst;
    VkResult r = createInstance(&ici, NULL, &inst);
    if (r != VK_SUCCESS) {
        printf("vkCreateInstance failed: %d\n\n", r);
        return;
    }
    PFN_vkEnumeratePhysicalDevices enumDevices =
        (PFN_vkEnumeratePhysicalDevices)gipa(inst, "vkEnumeratePhysicalDevices");
    PFN_vkGetPhysicalDeviceProperties getProps =
        (PFN_vkGetPhysicalDeviceProperties)gipa(inst, "vkGetPhysicalDeviceProperties");
    PFN_vkGetPhysicalDeviceProperties2 getProps2 =
        (PFN_vkGetPhysicalDeviceProperties2)gipa(inst, "vkGetPhysicalDeviceProperties2");
    PFN_vkEnumerateDeviceExtensionProperties enumExts =
        (PFN_vkEnumerateDeviceExtensionProperties)gipa(inst, "vkEnumerateDeviceExtensionProperties");
    PFN_vkDestroyInstance destroyInstance = (PFN_vkDestroyInstance)gipa(inst, "vkDestroyInstance");

    uint32_t count = 0;
    enumDevices(inst, &count, NULL);
    VkPhysicalDevice *devs = calloc(count ? count : 1, sizeof(*devs));
    enumDevices(inst, &count, devs);
    for (uint32_t i = 0; i < count; i++) {
        VkPhysicalDeviceProperties p;
        getProps(devs[i], &p);
        printf("device %u: %s\n", i, p.deviceName);
        printf("  apiVersion: %u.%u.%u, driverVersion: 0x%x, vendorID: 0x%x, deviceID: 0x%x\n",
               VK_VERSION_MAJOR(p.apiVersion), VK_VERSION_MINOR(p.apiVersion), VK_VERSION_PATCH(p.apiVersion),
               p.driverVersion, p.vendorID, p.deviceID);
        if (getProps2 && p.apiVersion >= VK_API_VERSION_1_2) {
            VkPhysicalDeviceDriverProperties drv = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES };
            VkPhysicalDeviceProperties2 p2 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &drv };
            getProps2(devs[i], &p2);
            printf("  driver: %s (%s)\n", drv.driverName, drv.driverInfo);
        }

        uint32_t n = 0;
        enumExts(devs[i], NULL, &n, NULL);
        VkExtensionProperties *exts = calloc(n ? n : 1, sizeof(*exts));
        enumExts(devs[i], NULL, &n, exts);
        printf("  forwarding checks:\n");
        for (size_t k = 0; k < sizeof(venus_exts) / sizeof(*venus_exts); k++) {
            int found = 0;
            for (uint32_t j = 0; j < n; j++)
                if (!strcmp(exts[j].extensionName, venus_exts[k])) found = 1;
            printf("    %-52s %s\n", venus_exts[k], found ? "yes" : "no");
        }
        printf("  extensions (%u):\n", n);
        for (uint32_t j = 0; j < n; j++) printf("    %s\n", exts[j].extensionName);
        free(exts);
    }
    free(devs);
    destroyInstance(inst, NULL);
    printf("\n");
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc > 2 && !strcmp(argv[1], "--angle")) {
        char egl[512], gles[512];
        snprintf(egl, sizeof(egl), "%s/libEGL_angle.so", argv[2]);
        snprintf(gles, sizeof(gles), "%s/libGLESv2_angle.so", argv[2]);
        report_gles("OpenGL ES (ANGLE)", egl, gles);
        return 0;
    }
    report_gles("OpenGL ES (system driver)", "libEGL.so", "libGLESv2.so");
    report_vulkan();
    return 0;
}
