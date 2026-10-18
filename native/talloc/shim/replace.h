/*
 * Minimal stand-in for Samba's lib/replace "replace.h", enough to build
 * talloc.c on its own for Android (bionic) and glibc. DeskDroid only needs
 * libtalloc for proot, so we skip Samba's waf configure step entirely.
 */
#ifndef DESKDROID_TALLOC_REPLACE_H
#define DESKDROID_TALLOC_REPLACE_H

#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#define HAVE_VA_COPY 1
#define HAVE_INTPTR_T 1
#define HAVE_CONSTRUCTOR_ATTRIBUTE 1
#define HAVE_GETAUXVAL 1
#define HAVE_SYS_AUXV_H 1

#ifndef _PUBLIC_
#define _PUBLIC_ __attribute__((visibility("default")))
#endif
#ifndef _PRIVATE_
#define _PRIVATE_ __attribute__((visibility("hidden")))
#endif

#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif
#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif

#ifndef discard_const
#define discard_const(ptr) ((void *)((uintptr_t)(ptr)))
#endif
#ifndef discard_const_p
#define discard_const_p(type, ptr) ((type *)discard_const(ptr))
#endif

#ifndef __has_attribute
#define __has_attribute(x) 0
#endif
#if __has_attribute(fallthrough)
#define FALL_THROUGH __attribute__((fallthrough))
#else
#define FALL_THROUGH ((void)0)
#endif

#endif
