// Appended to KWin's main_wayland.cpp: on Android kwin_wayland is a shared
// library that DeskDroid's QtHost loads into an app_process (Qt for Android
// needs a Java VM) and starts through this entry point, as it does the Qt demo.
#include <jni.h>
#include <string>
#include <vector>

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
    return kwinMain(int(args.size()), argv.data());
}
