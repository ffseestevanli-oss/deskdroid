// Offline check of every ViPER FX effect: each one gets 3 s of a test signal
// (a 60 Hz and a 1 kHz tone, an 8 kHz tone on the right, a little noise) and
// must give finite, non-silent output. Prints level changes and speed.
#include "ViperDsp.h"
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <utility>
#include <vector>
#include <string>
#include <algorithm>
using Settings = std::vector<std::pair<const char *, int>>;

static double band(const std::vector<float> &b, double f, int ch, size_t skip) {
    // Goertzel power at f.
    double w = 2 * M_PI * f / 48000, c = 2 * cos(w), s1 = 0, s2 = 0;
    size_t n = 0;
    for (size_t i = skip; i < b.size() / 2; i++, n++) { double s = b[i * 2 + ch] + c * s1 - s2; s2 = s1; s1 = s; }
    return sqrt(std::max(0.0, s1 * s1 + s2 * s2 - c * s1 * s2)) / n * 2;
}
static double db(double x) { return 20 * log10(std::max(x, 1e-9)); }

int main() {
    const size_t N = 48000 * 3;
    std::vector<float> in(N * 2);
    srand(1);
    for (size_t i = 0; i < N; i++) {
        double t = i / 48000.0, nz = (rand() / (double) RAND_MAX - 0.5) * 0.02;
        in[i * 2] = 0.2 * sin(2 * M_PI * 60 * t) + 0.2 * sin(2 * M_PI * 1000 * t) + nz;
        in[i * 2 + 1] = 0.2 * sin(2 * M_PI * 1000 * t) + 0.1 * sin(2 * M_PI * 8000 * t) + nz;
    }
    struct Case { const char *name; Settings s; };
    std::vector<Case> cases = {
        {"bypass (power on, nothing else)", {}},
        {"master volume 50%", {{"master.volume", 50}}},
        {"master pan full left", {{"master.pan", -100}}},
        {"limiter -6 dB", {{"master.limit", 50}}},
        {"playback gain control", {{"agc.enable", 1}, {"agc.ratio", 100}, {"agc.volume", 100}, {"agc.maxgain", 300}}},
        {"spectrum extension", {{"spectrum.enable", 1}, {"spectrum.strength", 50}}},
        {"FIR EQ +12 dB @band0, -12 dB @band5", {{"eq.enable", 1}, {"eq.band0", 1200}, {"eq.band5", -1200}}},
        {"field surround", {{"field.enable", 1}, {"field.widen", 300}, {"field.mid", 100}, {"field.depth", 300}}},
        {"differential surround", {{"diff.enable", 1}, {"diff.delay", 500}}},
        {"headphone surround+ level 0", {{"vhe.enable", 1}, {"vhe.level", 0}}},
        {"headphone surround+ level 2", {{"vhe.enable", 1}, {"vhe.level", 2}}},
        {"headphone surround+ level 4", {{"vhe.enable", 1}, {"vhe.level", 4}}},
        {"convolver (test IR: -6 dB echo)", {{"conv.enable", 1}}},
        {"reverberation", {{"reverb.enable", 1}, {"reverb.room", 50}, {"reverb.width", 50}, {"reverb.damp", 50}, {"reverb.wet", 40}, {"reverb.dry", 60}}},
        {"dynamic system", {{"dynsys.enable", 1}, {"dynsys.xlow", 140}, {"dynsys.xhigh", 6200}, {"dynsys.ylow", 40}, {"dynsys.yhigh", 60}, {"dynsys.sidex", 10}, {"dynsys.sidey", 80}, {"dynsys.strength", 50}}},
        {"tube simulator", {{"tube.enable", 1}}},
        {"ViPER bass natural", {{"bass.enable", 1}, {"bass.mode", 0}, {"bass.freq", 76}, {"bass.gain", 300}}},
        {"ViPER bass pure+", {{"bass.enable", 1}, {"bass.mode", 1}, {"bass.freq", 76}, {"bass.gain", 300}}},
        {"ViPER bass subwoofer", {{"bass.enable", 1}, {"bass.mode", 2}, {"bass.freq", 76}, {"bass.gain", 300}}},
        {"ViPER clarity natural", {{"clarity.enable", 1}, {"clarity.mode", 0}, {"clarity.gain", 200}}},
        {"ViPER clarity OZone+", {{"clarity.enable", 1}, {"clarity.mode", 1}, {"clarity.gain", 200}}},
        {"ViPER clarity XHiFi", {{"clarity.enable", 1}, {"clarity.mode", 2}, {"clarity.gain", 200}}},
        {"Cure+ crossfeed", {{"cure.enable", 1}, {"cure.level", 1}}},
        {"AnalogX", {{"analogx.enable", 1}, {"analogx.level", 1}}},
        {"speaker optimization", {{"speaker.enable", 1}}},
    };
    int bad = 0;
    printf("%-38s %8s %8s %8s %8s %8s %7s\n", "effect", "60Hz L", "1kHz L", "1kHz R", "8kHz R", "peak", "x real");
    for (auto &c : cases) {
        ViperDsp d(48000);
        d.set("master.enable", 1);
        if (std::string(c.name).rfind("convolver", 0) == 0) {
            std::vector<float> ir(9000, 0.0f); ir[0] = 0.5f; ir[8999] = 0.25f;
            d.setConvolver(ir, ir);
        }
        for (auto &kv : c.s) if (!d.set(kv.first, kv.second)) { printf("unknown key %s\n", kv.first); bad++; }
        std::vector<float> b = in;
        auto t0 = std::chrono::steady_clock::now();
        for (size_t off = 0; off < N; off += 512) d.process(b.data() + off * 2, std::min<size_t>(512, N - off));
        double secs = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        bool finite = true; double peak = 0, rms = 0;
        for (size_t i = 48000 * 2; i < b.size(); i++) { if (!std::isfinite(b[i])) finite = false; peak = std::max(peak, (double) fabs(b[i])); rms += b[i] * b[i]; }
        size_t sk = 48000;
        printf("%-38s %+7.1f %+8.1f %+8.1f %+8.1f %8.2f %7.0f%s\n", c.name,
               db(band(b, 60, 0, sk)) - db(band(in, 60, 0, sk)), db(band(b, 1000, 0, sk)) - db(band(in, 1000, 0, sk)),
               db(band(b, 1000, 1, sk)) - db(band(in, 1000, 1, sk)), db(band(b, 8000, 1, sk)) - db(band(in, 8000, 1, sk)),
               peak, 3.0 / secs, finite && rms > 1e-6 ? "" : "  <-- BAD");
        if (!finite || rms <= 1e-6) bad++;
    }
    std::vector<float> a, b;
    std::string vdc = "SR_44100:1,0,0,0,0\nSR_48000:1,0,0,0,0\n";
    printf("vdc parse: %s\n", ViperDsp::parseVdc(vdc, a, b) && a.size() == 5 ? "ok" : "FAILED");
    printf("%d problem(s)\n", bad);
    return bad ? 1 : 0;
}
