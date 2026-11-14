#include "PwEngine.h"

#include <pipewire/pipewire.h>
#include <pipewire/extensions/metadata.h>
#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>
#include <spa/utils/json.h>
#include <spa/utils/result.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>

namespace {
constexpr const char *kSinkName = "viperfx_sink";
constexpr const char *kOutputName = "viperfx_output";
constexpr const char *kGroup = "viperfx";
constexpr uint32_t kRate = 48000;

enum { H_CORE, H_REGISTRY, H_METADATA, H_CAPTURE, H_PLAYBACK, H_COUNT };

int64_t nowNs() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
               std::chrono::steady_clock::now().time_since_epoch()).count();
}

void peakMax(std::atomic<float> &a, float v) {
    float cur = a.load(std::memory_order_relaxed);
    while (v > cur && !a.compare_exchange_weak(cur, v, std::memory_order_relaxed)) {}
}

const struct spa_pod *audioFormat(struct spa_pod_builder *b) {
    struct spa_audio_info_raw info = {};
    info.format = SPA_AUDIO_FORMAT_F32;
    info.channels = 2;
    info.rate = kRate;
    info.position[0] = SPA_AUDIO_CHANNEL_FL;
    info.position[1] = SPA_AUDIO_CHANNEL_FR;
    return spa_format_audio_raw_build(b, SPA_PARAM_EnumFormat, &info);
}

// --- C callbacks into the engine ---
void captureProcess(void *data) { static_cast<PwEngine *>(data)->onProcess(); }
void playbackProcess(void *data) { static_cast<PwEngine *>(data)->onPlaybackProcess(); }

void captureParamChanged(void *data, uint32_t id, const struct spa_pod *param) {
    if (param == nullptr || id != SPA_PARAM_Format) return;
    struct spa_audio_info_raw info = {};
    if (spa_format_audio_raw_parse(param, &info) >= 0) static_cast<PwEngine *>(data)->onCaptureFormat(info.rate);
}

void streamState(void *, enum pw_stream_state, enum pw_stream_state, const char *) {}

const struct pw_stream_events captureEvents = [] {
    struct pw_stream_events e = {};
    e.version = PW_VERSION_STREAM_EVENTS;
    e.state_changed = streamState;
    e.param_changed = captureParamChanged;
    e.process = captureProcess;
    return e;
}();

const struct pw_stream_events playbackEvents = [] {
    struct pw_stream_events e = {};
    e.version = PW_VERSION_STREAM_EVENTS;
    e.state_changed = streamState;
    e.process = playbackProcess;
    return e;
}();

void registryGlobal(void *data, uint32_t id, uint32_t, const char *type, uint32_t, const struct spa_dict *props) {
    static_cast<PwEngine *>(data)->onGlobal(id, type, props);
}
void registryGlobalRemove(void *data, uint32_t id) { static_cast<PwEngine *>(data)->onGlobalRemove(id); }

const struct pw_registry_events registryEvents = [] {
    struct pw_registry_events e = {};
    e.version = PW_VERSION_REGISTRY_EVENTS;
    e.global = registryGlobal;
    e.global_remove = registryGlobalRemove;
    return e;
}();

int metadataProperty(void *data, uint32_t subject, const char *key, const char *type, const char *value) {
    static_cast<PwEngine *>(data)->onMetadataProperty(subject, key, type, value);
    return 0;
}

const struct pw_metadata_events metadataEvents = [] {
    struct pw_metadata_events e = {};
    e.version = PW_VERSION_METADATA_EVENTS;
    e.property = metadataProperty;
    return e;
}();

void coreError(void *data, uint32_t id, int seq, int res, const char *message) {
    static_cast<PwEngine *>(data)->onCoreError(id, seq, res, message);
}
void coreDone(void *data, uint32_t id, int seq) { static_cast<PwEngine *>(data)->onCoreDone(id, seq); }

const struct pw_core_events coreEvents = [] {
    struct pw_core_events e = {};
    e.version = PW_VERSION_CORE_EVENTS;
    e.done = coreDone;
    e.error = coreError;
    return e;
}();

// "{ \"name\": \"phone\" }" -> phone
std::string jsonName(const char *value) {
    if (value == nullptr) return {};
    struct spa_json it[2];
    spa_json_init(&it[0], value, strlen(value));
    if (spa_json_enter_object(&it[0], &it[1]) <= 0) return {};
    char key[64];
    while (spa_json_get_string(&it[1], key, sizeof(key)) > 0) {
        char val[512];
        if (strcmp(key, "name") == 0) {
            if (spa_json_get_string(&it[1], val, sizeof(val)) > 0) return val;
            return {};
        }
        const char *skip;
        if (spa_json_next(&it[1], &skip) <= 0) break;
    }
    return {};
}
}  // namespace

PwEngine::PwEngine() : dsp(kRate) {
    hooks = new spa_hook[H_COUNT];
    memset(hooks, 0, sizeof(spa_hook) * H_COUNT);
    scratch.resize(8192 * 2);
    ring.resize(kRingFrames * 2);
}

PwEngine::~PwEngine() {
    stop();
    delete[] hooks;
}

bool PwEngine::start(std::string *error) {
    if (started) return true;
    pw_init(nullptr, nullptr);
    loop = pw_thread_loop_new("viperfx", nullptr);
    if (loop == nullptr) { if (error) *error = "couldn't make PipeWire's loop"; return false; }
    context = pw_context_new(pw_thread_loop_get_loop(loop), nullptr, 0);
    if (context == nullptr) {
        if (error) *error = "couldn't start PipeWire's client";
        pw_thread_loop_destroy(loop); loop = nullptr;
        return false;
    }
    if (pw_thread_loop_start(loop) < 0) {
        if (error) *error = "couldn't start PipeWire's thread";
        pw_context_destroy(context); context = nullptr;
        pw_thread_loop_destroy(loop); loop = nullptr;
        return false;
    }
    pw_thread_loop_lock(loop);
    core = pw_context_connect(context, pw_properties_new(PW_KEY_APP_NAME, "ViPER FX", nullptr), 0);
    if (core == nullptr) {
        pw_thread_loop_unlock(loop);
        if (error) *error = "no PipeWire sound server (DeskDroid build 1095 or newer has it)";
        stop();
        return false;
    }
    pw_core_add_listener(core, &hooks[H_CORE], &coreEvents, this);
    registry = pw_core_get_registry(core, PW_VERSION_REGISTRY, 0);
    pw_registry_add_listener(registry, &hooks[H_REGISTRY], &registryEvents, this);

    // The sink programs play into.
    capture = pw_stream_new(core, "ViPER FX",
        pw_properties_new(
            PW_KEY_MEDIA_CLASS, "Audio/Sink",
            PW_KEY_NODE_NAME, kSinkName,
            PW_KEY_NODE_DESCRIPTION, "ViPER FX",
            PW_KEY_NODE_GROUP, kGroup,
            PW_KEY_NODE_LINK_GROUP, kGroup,
            PW_KEY_NODE_VIRTUAL, "true",
            PW_KEY_PRIORITY_SESSION, "2500",
            PW_KEY_PRIORITY_DRIVER, "2500",
            SPA_KEY_AUDIO_POSITION, "[ FL FR ]",
            PW_KEY_APP_ICON_NAME, "org.deskdroid.ViperFX",
            nullptr));
    pw_stream_add_listener(capture, &hooks[H_CAPTURE], &captureEvents, this);
    uint8_t buf[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof(buf));
    const struct spa_pod *params[1] = {audioFormat(&b)};
    int res = pw_stream_connect(capture, PW_DIRECTION_INPUT, PW_ID_ANY,
        static_cast<enum pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS),
        params, 1);
    if (res < 0) {
        pw_thread_loop_unlock(loop);
        if (error) *error = std::string("couldn't make the ViPER FX sink: ") + spa_strerror(res);
        stop();
        return false;
    }
    // The playback side connects once the registry has listed the sinks.
    syncSeq = pw_core_sync(core, PW_ID_CORE, 0);
    started = true;
    pw_thread_loop_unlock(loop);
    return true;
}

void PwEngine::onCoreDone(uint32_t id, int seq) {
    if (loop) pw_thread_loop_signal(loop, false);
    if (id != PW_ID_CORE || seq != syncSeq || synced) return;
    synced = true;
    connectPlayback();
    setDefaultSink(kSinkName);
}

std::string PwEngine::pickOutput() const {
    // DeskDroid's phone sink, else the default before ours, else any other sink.
    for (const Sink &s : sinks) if (s.name == "phone") return s.name;
    if (haveConfiguredDefault && configuredDefault != kSinkName)
        for (const Sink &s : sinks) if (s.name == configuredDefault) return s.name;
    for (const Sink &s : sinks) if (s.name != kSinkName) return s.name;
    return {};
}

void PwEngine::connectPlayback() {
    if (playback != nullptr) return;
    const char *forced = getenv("VIPERFX_TARGET");
    std::string target = forced && *forced ? forced : pickOutput();
    {
        std::lock_guard<std::mutex> g(infoLock);
        output = target;
    }
    struct pw_properties *props = pw_properties_new(
        PW_KEY_MEDIA_CLASS, "Stream/Output/Audio",
        PW_KEY_NODE_NAME, kOutputName,
        PW_KEY_NODE_DESCRIPTION, "ViPER FX output",
        PW_KEY_NODE_GROUP, kGroup,
        PW_KEY_NODE_LINK_GROUP, kGroup,
        PW_KEY_NODE_DONT_RECONNECT, "true",
        SPA_KEY_AUDIO_POSITION, "[ FL FR ]",
        "stream.dont-remix", "true",
        nullptr);
    if (!target.empty()) pw_properties_set(props, PW_KEY_TARGET_OBJECT, target.c_str());
    playback = pw_stream_new(core, "ViPER FX output", props);
    pw_stream_add_listener(playback, &hooks[H_PLAYBACK], &playbackEvents, this);
    uint8_t buf[1024];
    struct spa_pod_builder b = SPA_POD_BUILDER_INIT(buf, sizeof(buf));
    const struct spa_pod *params[1] = {audioFormat(&b)};
    int res = pw_stream_connect(playback, PW_DIRECTION_OUTPUT, PW_ID_ANY,
        static_cast<enum pw_stream_flags>(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS),
        params, 1);
    if (res < 0) {
        std::lock_guard<std::mutex> g(infoLock);
        problemText = std::string("couldn't connect to the speaker: ") + spa_strerror(res);
    }
}

void PwEngine::setDefaultSink(const std::string &name) {
    if (metadata == nullptr) return;
    std::string json = "{ \"name\": \"" + name + "\" }";
    pw_metadata_set_property(reinterpret_cast<struct pw_metadata *>(metadata), PW_ID_CORE,
                             "default.configured.audio.sink", "Spa:String:JSON", json.c_str());
    weSetDefault = name == kSinkName;
}

void PwEngine::onGlobal(uint32_t id, const char *type, const struct spa_dict *props) {
    if (props == nullptr) return;
    if (strcmp(type, PW_TYPE_INTERFACE_Node) == 0) {
        const char *cls = spa_dict_lookup(props, PW_KEY_MEDIA_CLASS);
        const char *name = spa_dict_lookup(props, PW_KEY_NODE_NAME);
        if (cls && name && strcmp(cls, "Audio/Sink") == 0) sinks.push_back({id, name});
    } else if (strcmp(type, PW_TYPE_INTERFACE_Metadata) == 0 && metadata == nullptr) {
        const char *name = spa_dict_lookup(props, PW_KEY_METADATA_NAME);
        if (name && strcmp(name, "default") == 0) {
            metadata = static_cast<pw_proxy *>(pw_registry_bind(registry, id, PW_TYPE_INTERFACE_Metadata, PW_VERSION_METADATA, 0));
            metadataId = id;
            if (metadata) pw_metadata_add_listener(reinterpret_cast<struct pw_metadata *>(metadata), &hooks[H_METADATA], &metadataEvents, this);
            if (synced) setDefaultSink(kSinkName);
        }
    }
}

void PwEngine::onGlobalRemove(uint32_t id) {
    sinks.erase(std::remove_if(sinks.begin(), sinks.end(), [id](const Sink &s) { return s.id == id; }), sinks.end());
}

void PwEngine::onMetadataProperty(uint32_t subject, const char *key, const char *, const char *value) {
    if (subject != PW_ID_CORE || key == nullptr) return;
    if (strcmp(key, "default.configured.audio.sink") == 0) {
        std::string n = jsonName(value);
        // Remember what was default before ViPER FX, to give it back on stop.
        if (n != kSinkName) { configuredDefault = n; haveConfiguredDefault = true; }
    }
}

void PwEngine::onCoreError(uint32_t id, int, int res, const char *message) {
    if (id != PW_ID_CORE) return;
    std::lock_guard<std::mutex> g(infoLock);
    problemText = std::string("sound server: ") + (message ? message : spa_strerror(res));
}

void PwEngine::onCaptureFormat(uint32_t rate) {
    if (rate == 0) return;
    post([rate](ViperDsp &d) { d.setSamplingRate(rate); });
}

void PwEngine::post(DspCall fn) {
    std::lock_guard<std::mutex> g(queueLock);
    queue.push_back(std::move(fn));
}

void PwEngine::onProcess() {
    // Settings first (skipped this block if the app is adding some right now).
    if (queueLock.try_lock()) {
        std::vector<DspCall> calls;
        calls.swap(queue);
        queueLock.unlock();
        for (auto &c : calls) c(dsp);
    }
    struct pw_buffer *in = pw_stream_dequeue_buffer(capture);
    if (in == nullptr) return;
    struct spa_data &di = in->buffer->datas[0];
    if (di.data != nullptr && di.chunk != nullptr) {
        uint32_t off = std::min(di.chunk->offset, di.maxsize);
        uint32_t frames = std::min(di.chunk->size, di.maxsize - off) / (2 * sizeof(float));
        frames = std::min<uint32_t>(frames, (uint32_t) scratch.size() / 2);
        float *buf = scratch.data();
        memcpy(buf, static_cast<uint8_t *>(di.data) + off, frames * 2 * sizeof(float));
        float il = 0, ir = 0, ol = 0, orr = 0;
        for (uint32_t i = 0; i < frames; i++) {
            il = std::max(il, std::fabs(buf[i * 2]));
            ir = std::max(ir, std::fabs(buf[i * 2 + 1]));
        }
        dsp.process(buf, frames);
        for (uint32_t i = 0; i < frames; i++) {
            ol = std::max(ol, std::fabs(buf[i * 2]));
            orr = std::max(orr, std::fabs(buf[i * 2 + 1]));
        }
        peakMax(pInL, il); peakMax(pInR, ir); peakMax(pOutL, ol); peakMax(pOutR, orr);
        if (il > 1e-5f || ir > 1e-5f) lastBlockNs.store(nowNs(), std::memory_order_relaxed);
        // Into the ring; if the output side stalled, drop the oldest sound.
        uint64_t w = ringWrite.load(std::memory_order_relaxed);
        uint64_t r = ringRead.load(std::memory_order_acquire);
        if (w + frames - r > kRingFrames) ringRead.store(w + frames - kRingFrames, std::memory_order_release);
        for (uint32_t i = 0; i < frames; i++) {
            uint32_t at = (uint32_t) ((w + i) % kRingFrames) * 2;
            ring[at] = buf[i * 2];
            ring[at + 1] = buf[i * 2 + 1];
        }
        ringWrite.store(w + frames, std::memory_order_release);
    }
    pw_stream_queue_buffer(capture, in);
}

void PwEngine::onPlaybackProcess() {
    struct pw_buffer *out = pw_stream_dequeue_buffer(playback);
    if (out == nullptr) return;
    struct spa_data &dd = out->buffer->datas[0];
    float *dst = static_cast<float *>(dd.data);
    if (dst != nullptr && dd.chunk != nullptr) {
        uint32_t want = dd.maxsize / (2 * sizeof(float));
        if (out->requested) want = std::min<uint32_t>(want, (uint32_t) out->requested);
        uint64_t r = ringRead.load(std::memory_order_acquire);
        uint64_t w = ringWrite.load(std::memory_order_acquire);
        // Keep the delay short: more than two blocks waiting means we fell behind.
        if (w - r > (uint64_t) want * 3) r = w - want * 2;
        uint32_t have = (uint32_t) std::min<uint64_t>(w - r, want);
        for (uint32_t i = 0; i < have; i++) {
            uint32_t at = (uint32_t) ((r + i) % kRingFrames) * 2;
            dst[i * 2] = ring[at];
            dst[i * 2 + 1] = ring[at + 1];
        }
        if (have < want) memset(dst + have * 2, 0, (want - have) * 2 * sizeof(float));
        ringRead.store(r + have, std::memory_order_release);
        dd.chunk->offset = 0;
        dd.chunk->stride = 2 * sizeof(float);
        dd.chunk->size = want * 2 * sizeof(float);
    }
    pw_stream_queue_buffer(playback, out);
}

void PwEngine::takePeaks(float &inL, float &inR, float &outL, float &outR) {
    inL = pInL.exchange(0); inR = pInR.exchange(0);
    outL = pOutL.exchange(0); outR = pOutR.exchange(0);
}

bool PwEngine::flowing() const {
    return nowNs() - lastBlockNs.load(std::memory_order_relaxed) < 500000000LL;
}

std::string PwEngine::outputName() const {
    std::lock_guard<std::mutex> g(infoLock);
    return output;
}

std::string PwEngine::problem() const {
    std::lock_guard<std::mutex> g(infoLock);
    return problemText;
}

void PwEngine::stop() {
    if (loop == nullptr) return;
    pw_thread_loop_lock(loop);
    // Give the default sink back before the ViPER FX sink goes away.
    if (weSetDefault && metadata != nullptr) {
        std::string back = haveConfiguredDefault && configuredDefault != kSinkName ? configuredDefault : pickOutput();
        if (back.empty()) pw_metadata_set_property(reinterpret_cast<struct pw_metadata *>(metadata), PW_ID_CORE,
                                                   "default.configured.audio.sink", nullptr, nullptr);
        else setDefaultSink(back);
        weSetDefault = false;
        if (core) {
            // Wait for the server to take it before leaving.
            syncSeq = pw_core_sync(core, PW_ID_CORE, 0);
            pw_thread_loop_timed_wait(loop, 1);
        }
    }
    if (capture) { pw_stream_destroy(capture); capture = nullptr; }
    if (playback) { pw_stream_destroy(playback); playback = nullptr; }
    if (metadata) { pw_proxy_destroy(metadata); metadata = nullptr; }
    if (registry) { pw_proxy_destroy(reinterpret_cast<pw_proxy *>(registry)); registry = nullptr; }
    if (core) { pw_core_disconnect(core); core = nullptr; }
    pw_thread_loop_unlock(loop);
    pw_thread_loop_stop(loop);
    if (context) { pw_context_destroy(context); context = nullptr; }
    pw_thread_loop_destroy(loop);
    loop = nullptr;
    sinks.clear();
    synced = false;
    started = false;
}
