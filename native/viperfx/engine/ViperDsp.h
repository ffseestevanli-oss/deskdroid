// ViperDsp: the ViPER FX effects (ViPERFX_RE's reimplementation of
// ViPER4Android's DSP) behind one string-keyed setting API, the same keys the
// app's settings and presets use. Values are integers in the units the
// original ViPER4Android app sent (percent, centi-dB, Hz, ms*100...).
//
// Not thread-safe: set() and process() must be called from the same thread
// (the PipeWire engine queues settings and applies them in its process call).
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

class ViPER;

class ViperDsp {
public:
    explicit ViperDsp(uint32_t samplingRate = 48000);
    ~ViperDsp();

    void setSamplingRate(uint32_t samplingRate);
    uint32_t samplingRate() const { return rate; }

    // Returns false for an unknown key.
    bool set(const std::string &key, int value);

    // ViPER-DDC coefficients (a .vdc file, parsed by parseVdc()).
    void setDdc(const std::vector<float> &c44100, const std::vector<float> &c48000);

    // Convolver impulse response at the current sampling rate, one kernel per
    // channel (the same for both from a mono file). Empty clears it.
    void setConvolver(const std::vector<float> &left, const std::vector<float> &right);

    // In place, interleaved stereo float, any frame count.
    void process(float *interleaved, uint32_t frames);
    void reset();

    bool enabled() const { return master; }

    // A ViPER-DDC file: "SR_44100:c,c,c..." and "SR_48000:c,c,c..." lines,
    // the same number of coefficients in each. False if it isn't one.
    static bool parseVdc(const std::string &text, std::vector<float> &c44100,
                         std::vector<float> &c48000, std::string *error = nullptr);

    // Every key set() takes, for the app and tests.
    static const std::vector<std::string> &keys();

private:
    void applyGain();
    void applyDynamicSystem();

    std::unique_ptr<ViPER> viper;
    uint32_t rate;
    bool master = false;
    int volume = 100, pan = 0;
    int dsX[2] = {100, 5600}, dsY[2] = {40, 80}, dsSide[2] = {50, 50};
    std::vector<float> chunk;
};
