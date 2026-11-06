// Appended to KWin's main_wayland.cpp: on Android kwin_wayland is a shared
// library that DeskDroid's QtHost loads into an app_process (Qt for Android
// needs a Java VM) and starts through this entry point, as it does the Qt demo.
#include <dlfcn.h>
#include <jni.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unwind.h>
#include <string>
#include <vector>

// Qt for Android logs to logcat; DeskDroid shows a process's output instead.
static void logToStderr(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    static const char *const names[] = {"debug", "warning", "critical", "fatal", "info"};
    const bool category = context.category && strcmp(context.category, "default") != 0;
    fprintf(stderr, "%s: %s%s%s\n", names[type < 5 ? type : 0], category ? context.category : "", category ? ": " : "",
            message.toLocal8Bit().constData());
    fflush(stderr);
}

static _Unwind_Reason_Code printFrame(_Unwind_Context *context, void *arg)
{
    int &frames = *static_cast<int *>(arg);
    const uintptr_t pc = _Unwind_GetIP(context);
    Dl_info info;
    if (pc && dladdr(reinterpret_cast<void *>(pc), &info) && info.dli_fname) {
        const char *file = strrchr(info.dli_fname, '/');
        fprintf(stderr, "  %s+0x%lx %s\n", file ? file + 1 : info.dli_fname,
                static_cast<unsigned long>(pc - reinterpret_cast<uintptr_t>(info.dli_fbase)), info.dli_sname ? info.dli_sname : "");
    }
    return ++frames < 24 ? _URC_NO_REASON : _URC_END_OF_STACK;
}

// A crash prints where it happened (library+offset and symbol), then dies as usual.
static void onCrash(int sig)
{
    fprintf(stderr, "crash: signal %d (%s)\n", sig, strsignal(sig));
    int frames = 0;
    _Unwind_Backtrace(printFrame, &frames);
    fflush(stderr);
    signal(sig, SIG_DFL);
    raise(sig);
}

extern "C" __attribute__((visibility("default"))) jint Java_io_deskdroid_app_QtHost_run(JNIEnv *env, jclass, jobjectArray jargs)
{
    static std::vector<std::string> args; // Qt keeps argv for the app's lifetime
    static std::vector<char *> argv;
    args.push_back("kwin_wayland");
    for (jsize i = 0, n = env->GetArrayLength(jargs); i < n; i++) {
        auto js = static_cast<jstring>(env->GetObjectArrayElement(jargs, i));
        const char *c = env->GetStringUTFChars(js, nullptr);
        args.emplace_back(c);
        env->ReleaseStringUTFChars(js, c);
    }
    for (auto &a : args) {
        argv.push_back(a.data());
    }
    argv.push_back(nullptr);
    qInstallMessageHandler(logToStderr);
    for (int sig : {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE}) {
        signal(sig, onCrash);
    }
    return kwinMain(int(args.size()), argv.data());
}
