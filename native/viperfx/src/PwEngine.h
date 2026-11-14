// PwEngine: ViPER FX in the PipeWire graph, the way EasyEffects and
// PipeWire's loopback module do it. A virtual sink, "ViPER FX", takes the
// programs' sound (it becomes the default sink while the engine runs); every
// cycle its input goes through ViperDsp and out of a playback stream into the
// real sink (DeskDroid's "Phone"). No root, no Android audio effect.
#pragma once

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

#include "ViperDsp.h"

struct pw_thread_loop;
struct pw_context;
struct pw_core;
struct pw_registry;
struct pw_stream;
struct pw_proxy;
struct spa_hook;

class PwEngine {
public:
    using DspCall = std::function<void(ViperDsp &)>;

    PwEngine();
    ~PwEngine();

    // Connects to the sound server and makes the sink. False with a reason.
    bool start(std::string *error);
    void stop();
    bool running() const { return started; }

    // Runs fn on the audio thread before the next block (settings, kernels).
    void post(DspCall fn);

    // Peak levels of the last blocks (0..1), read and reset by the app.
    void takePeaks(float &inL, float &inR, float &outL, float &outR);
    // Whether sound went through recently, and where it goes.
    bool flowing() const;
    std::string outputName() const;
    // Something the app should show (lost the server...); empty when fine.
    std::string problem() const;

    // Internal: PipeWire callbacks.
    void onProcess();          // the sink: programs' sound in, effects, into the ring
    void onPlaybackProcess();  // the output: the ring into the real sink
    void onGlobal(uint32_t id, const char *type, const struct spa_dict *props);
    void onGlobalRemove(uint32_t id);
    void onMetadataProperty(uint32_t subject, const char *key, const char *type, const char *value);
    void onCoreError(uint32_t id, int seq, int res, const char *message);
    void onCaptureFormat(uint32_t rate);
    void onCoreDone(uint32_t id, int seq);

private:
    void connectPlayback();
    void setDefaultSink(const std::string &name);
    std::string pickOutput() const;

    pw_thread_loop *loop = nullptr;
    pw_context *context = nullptr;
    pw_core *core = nullptr;
    pw_registry *registry = nullptr;
    pw_stream *capture = nullptr;
    pw_stream *playback = nullptr;
    pw_proxy *metadata = nullptr;
    spa_hook *hooks = nullptr;  // core, registry, metadata, capture, playback
    bool started = false;
    int syncSeq = -1;
    bool synced = false;

    struct Sink { uint32_t id; std::string name; };
    std::vector<Sink> sinks;
    uint32_t metadataId = 0;
    std::string configuredDefault;  // the default sink before ours
    bool haveConfiguredDefault = false;
    bool weSetDefault = false;
    std::string output;

    ViperDsp dsp;
    std::mutex queueLock;
    std::vector<DspCall> queue;
    std::atomic<float> pInL{0}, pInR{0}, pOutL{0}, pOutR{0};
    std::atomic<int64_t> lastBlockNs{0};
    mutable std::mutex infoLock;
    std::string problemText;
    std::vector<float> scratch;
    // Processed sound between the two sides (their block sizes can differ).
    // Both run on PipeWire's data thread; the atomics keep it safe anyway.
    static constexpr uint32_t kRingFrames = 16384;
    std::vector<float> ring;
    std::atomic<uint64_t> ringWrite{0}, ringRead{0};
};
