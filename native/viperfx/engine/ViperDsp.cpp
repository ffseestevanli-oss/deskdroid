#include "ViperDsp.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <sstream>

#include "viper/ViPER.h"

namespace {
int clampi(int v, int lo, int hi) { return std::max(lo, std::min(hi, v)); }
float pct(int v) { return static_cast<float>(v) / 100.0f; }
constexpr uint32_t kChunk = 1024;  // ViPER's buffers hold 4096 frames
}

ViperDsp::ViperDsp(uint32_t samplingRate) : viper(new ViPER()), rate(samplingRate) {
    viper->setSamplingRate(rate);
    viper->reset();
    viper->setGain(1.0f, 1.0f);
    viper->setThresholdLimit(1.0f);
    chunk.resize(kChunk * 2);
}

ViperDsp::~ViperDsp() = default;

void ViperDsp::setSamplingRate(uint32_t samplingRate) {
    if (samplingRate == 0 || samplingRate == rate) return;
    rate = samplingRate;
    viper->setSamplingRate(rate);
    viper->reset();
}

void ViperDsp::reset() { viper->reset(); }

void ViperDsp::applyGain() {
    float v = pct(volume);
    float p = pct(pan);
    float l = v, r = v;
    if (p < 0) r = v * (1.0f + p);
    else l = v * (1.0f - p);
    viper->setGain(l, r);
}

void ViperDsp::applyDynamicSystem() {
    viper->dynamicSystem.SetXCoeffs(dsX[0], dsX[1]);
    viper->dynamicSystem.SetYCoeffs(dsY[0], dsY[1]);
    viper->dynamicSystem.SetSideGain(pct(dsSide[0]), pct(dsSide[1]));
}

const std::vector<std::string> &ViperDsp::keys() {
    static const std::vector<std::string> k = {
        "master.enable", "master.volume", "master.pan", "master.limit",
        "agc.enable", "agc.ratio", "agc.volume", "agc.maxgain",
        "ddc.enable", "conv.enable",
        "spectrum.enable", "spectrum.strength",
        "eq.enable", "eq.band0", "eq.band1", "eq.band2", "eq.band3", "eq.band4",
        "eq.band5", "eq.band6", "eq.band7", "eq.band8", "eq.band9",
        "field.enable", "field.widen", "field.mid", "field.depth",
        "diff.enable", "diff.delay",
        "vhe.enable", "vhe.level",
        "reverb.enable", "reverb.room", "reverb.width", "reverb.damp", "reverb.wet", "reverb.dry",
        "dynsys.enable", "dynsys.xlow", "dynsys.xhigh", "dynsys.ylow", "dynsys.yhigh",
        "dynsys.sidex", "dynsys.sidey", "dynsys.strength",
        "tube.enable",
        "bass.enable", "bass.mode", "bass.freq", "bass.gain",
        "clarity.enable", "clarity.mode", "clarity.gain",
        "cure.enable", "cure.level",
        "analogx.enable", "analogx.level",
        "speaker.enable",
    };
    return k;
}

bool ViperDsp::set(const std::string &key, int v) {
    ViPER &x = *viper;
    const bool on = v != 0;
    // Master: power, output volume and pan, limiter.
    if (key == "master.enable") {
        if (on && !master) x.reset();
        master = on;
    } else if (key == "master.volume") { volume = clampi(v, 0, 400); applyGain(); }
    else if (key == "master.pan") { pan = clampi(v, -100, 100); applyGain(); }
    else if (key == "master.limit") x.setThresholdLimit(pct(clampi(v, 1, 100)));
    // Playback gain control.
    else if (key == "agc.enable") x.playbackGain.SetEnable(on);
    else if (key == "agc.ratio") x.playbackGain.SetRatio(pct(clampi(v, 1, 1000)));
    else if (key == "agc.volume") x.playbackGain.SetVolume(pct(clampi(v, 1, 100)));
    else if (key == "agc.maxgain") x.playbackGain.SetMaxGainFactor(pct(clampi(v, 100, 1000)));
    // ViPER-DDC (its coefficients come from setDdc()).
    else if (key == "ddc.enable") x.viperDdc.SetEnable(on);
    // Convolver (its impulse response comes from setConvolver()).
    else if (key == "conv.enable") x.convolver.SetEnable(on);
    // Spectrum extension.
    else if (key == "spectrum.enable") x.spectrumExtend.SetEnable(on);
    else if (key == "spectrum.strength") x.spectrumExtend.SetExciter(pct(clampi(v, 0, 100)));
    // FIR equalizer: 10 bands, centi-dB.
    else if (key == "eq.enable") x.iirFilter.SetEnable(on);
    else if (key.rfind("eq.band", 0) == 0 && key.size() == 8 && key[7] >= '0' && key[7] <= '9')
        x.iirFilter.SetBandLevel(static_cast<uint32_t>(key[7] - '0'), pct(clampi(v, -1200, 1200)));
    // Field surround.
    else if (key == "field.enable") x.colorfulMusic.SetEnable(on);
    else if (key == "field.widen") x.colorfulMusic.SetWidenValue(pct(clampi(v, 0, 800)));
    else if (key == "field.mid") x.colorfulMusic.SetMidImageValue(pct(clampi(v, 0, 1000)));
    else if (key == "field.depth") x.colorfulMusic.SetDepthValue(static_cast<short>(clampi(v, 0, 1000)));
    // Differential surround: delay in ms * 100.
    else if (key == "diff.enable") x.diffSurround.SetEnable(on);
    else if (key == "diff.delay") x.diffSurround.SetDelayTime(pct(clampi(v, 100, 2000)));
    // Headphone surround+.
    else if (key == "vhe.enable") x.vhe.SetEnable(on);
    else if (key == "vhe.level") x.vhe.SetEffectLevel(static_cast<uint32_t>(clampi(v, 0, 4)));
    // Reverberation.
    else if (key == "reverb.enable") x.reverberation.SetEnable(on);
    else if (key == "reverb.room") x.reverberation.SetRoomSize(pct(clampi(v, 0, 100)));
    else if (key == "reverb.width") x.reverberation.SetWidth(pct(clampi(v, 0, 100)));
    else if (key == "reverb.damp") x.reverberation.SetDamp(pct(clampi(v, 0, 100)));
    else if (key == "reverb.wet") x.reverberation.SetWet(pct(clampi(v, 0, 100)));
    else if (key == "reverb.dry") x.reverberation.SetDry(pct(clampi(v, 0, 100)));
    // Dynamic system.
    else if (key == "dynsys.enable") x.dynamicSystem.SetEnable(on);
    else if (key == "dynsys.xlow") { dsX[0] = clampi(v, 1, 24000); applyDynamicSystem(); }
    else if (key == "dynsys.xhigh") { dsX[1] = clampi(v, 1, 24000); applyDynamicSystem(); }
    else if (key == "dynsys.ylow") { dsY[0] = clampi(v, 1, 24000); applyDynamicSystem(); }
    else if (key == "dynsys.yhigh") { dsY[1] = clampi(v, 1, 24000); applyDynamicSystem(); }
    else if (key == "dynsys.sidex") { dsSide[0] = clampi(v, 0, 100); applyDynamicSystem(); }
    else if (key == "dynsys.sidey") { dsSide[1] = clampi(v, 0, 100); applyDynamicSystem(); }
    else if (key == "dynsys.strength") x.dynamicSystem.SetBassGain(pct(clampi(v, 0, 100)));
    // Tube simulator.
    else if (key == "tube.enable") x.tubeSimulator.SetEnable(on);
    // ViPER Bass: mode 0 natural, 1 pure bass+, 2 subwoofer; speaker size in Hz.
    else if (key == "bass.enable") x.viperBass.SetEnable(on);
    else if (key == "bass.mode") x.viperBass.SetProcessMode(static_cast<ViPERBass::ProcessMode>(clampi(v, 0, 2)));
    else if (key == "bass.freq") x.viperBass.SetSpeaker(static_cast<uint32_t>(clampi(v, 15, 300)));
    else if (key == "bass.gain") x.viperBass.SetBassFactor(pct(clampi(v, 0, 1000)));
    // ViPER Clarity: mode 0 natural, 1 OZone+, 2 XHiFi.
    else if (key == "clarity.enable") x.viperClarity.SetEnable(on);
    else if (key == "clarity.mode") x.viperClarity.SetProcessMode(static_cast<ViPERClarity::ClarityMode>(clampi(v, 0, 2)));
    else if (key == "clarity.gain") x.viperClarity.SetClarity(pct(clampi(v, 0, 1000)));
    // Auditory system protection (Cure+ crossfeed): 0 slight, 1 moderate, 2 extreme.
    else if (key == "cure.enable") x.cure.SetEnable(on);
    else if (key == "cure.level") {
        static const Crossfeed::Preset presets[3] = {{650, 95}, {700, 60}, {700, 45}};
        x.cure.SetPreset(presets[clampi(v, 0, 2)]);
    }
    // AnalogX.
    else if (key == "analogx.enable") x.analogX.SetEnable(on);
    else if (key == "analogx.level") x.analogX.SetProcessingModel(clampi(v, 0, 2));
    // Speaker optimization.
    else if (key == "speaker.enable") x.speakerCorrection.SetEnable(on);
    else return false;
    return true;
}

void ViperDsp::setDdc(const std::vector<float> &c44100, const std::vector<float> &c48000) {
    if (c44100.empty() || c44100.size() != c48000.size()) return;
    viper->viperDdc.SetCoeffs(static_cast<uint32_t>(c44100.size()), c44100.data(), c48000.data());
}

void ViperDsp::setConvolver(const std::vector<float> &left, const std::vector<float> &right) {
    if (left.size() < 16 || left.size() != right.size()) {
        viper->convolver.SetEnable(false);
        return;
    }
    viper->convolver.SetKernelStereo(const_cast<float *>(left.data()), const_cast<float *>(right.data()),
                                     static_cast<uint32_t>(left.size()));
}

void ViperDsp::process(float *buf, uint32_t frames) {
    if (!master) return;
    while (frames > 0) {
        uint32_t n = std::min(frames, kChunk);
        viper->process(buf, n);
        // A NaN or Inf from an effect would stay in its filters forever: start over.
        for (uint32_t i = 0; i < n * 2; i++) {
            if (!std::isfinite(buf[i])) {
                std::memset(buf, 0, n * 2 * sizeof(float));
                viper->reset();
                break;
            }
        }
        buf += n * 2;
        frames -= n;
    }
}

bool ViperDsp::parseVdc(const std::string &text, std::vector<float> &c44100,
                        std::vector<float> &c48000, std::string *error) {
    auto parse = [](const std::string &list, std::vector<float> &out) {
        out.clear();
        std::stringstream ss(list);
        std::string item;
        while (std::getline(ss, item, ',')) {
            item.erase(0, item.find_first_not_of(" \t\r\n"));
            if (item.empty()) continue;
            char *end = nullptr;
            float f = std::strtof(item.c_str(), &end);
            if (end == item.c_str()) return false;
            out.push_back(f);
        }
        return !out.empty();
    };
    c44100.clear();
    c48000.clear();
    std::stringstream lines(text);
    std::string line;
    bool got44 = false, got48 = false;
    while (std::getline(lines, line)) {
        if (line.rfind("SR_44100:", 0) == 0) got44 = parse(line.substr(9), c44100);
        else if (line.rfind("SR_48000:", 0) == 0) got48 = parse(line.substr(9), c48000);
    }
    if (!got44 || !got48) {
        if (error) *error = "not a ViPER-DDC file (no SR_44100 and SR_48000 lines)";
        return false;
    }
    if (c44100.size() != c48000.size() || c44100.size() % 5 != 0) {
        if (error) *error = "the 44.1 and 48 kHz coefficient lists don't match";
        return false;
    }
    return true;
}
