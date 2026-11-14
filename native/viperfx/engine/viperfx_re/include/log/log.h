// Android's liblog, for ViPERFX_RE on desktop Linux: messages go to stderr
// when VIPERFX_DEBUG is set, nowhere otherwise.
#pragma once
#include <cstdio>
#include <cstdlib>
#define VIPERFX_LOG_(lvl, ...) do { if (getenv("VIPERFX_DEBUG")) { fprintf(stderr, "viperfx " lvl ": " __VA_ARGS__); fputc('\n', stderr); } } while (0)
#define ALOGD(...) VIPERFX_LOG_("D", __VA_ARGS__)
#define ALOGI(...) VIPERFX_LOG_("I", __VA_ARGS__)
#define ALOGW(...) VIPERFX_LOG_("W", __VA_ARGS__)
#define ALOGE(...) VIPERFX_LOG_("E", __VA_ARGS__)
#define ALOGV(...) do {} while (0)
