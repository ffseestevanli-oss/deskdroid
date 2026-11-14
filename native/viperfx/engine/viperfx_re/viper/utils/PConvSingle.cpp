#include <cmath>
#include <cstring>
#include "PConvSingle.h"

// Uniformly partitioned overlap-save convolution: the kernel is cut into
// segmentCount partitions of segmentSize samples, each transformed once with
// an FFT of 2 * segmentSize; every block of input is transformed, multiplied
// with each partition against the matching older input block, summed, and
// transformed back. Latency is one block (the callers buffer for it).

PConvSingle::PConvSingle() {
    this->instanceUsable = false;
    this->segmentCount = 0;
    this->segmentSize = 0;
    this->data = nullptr;
}

PConvSingle::~PConvSingle() {
    ReleaseResources();
}

void PConvSingle::fft(std::vector<std::complex<float>> &a, bool inverse) {
    const int n = this->data->fftSize;
    const std::vector<int> &rev = this->data->bitrev;
    for (int i = 0; i < n; i++) {
        if (i < rev[i]) std::swap(a[i], a[rev[i]]);
    }
    const std::vector<std::complex<float>> &tw = this->data->twiddles;
    for (int len = 2; len <= n; len <<= 1) {
        const int half = len >> 1, step = n / len;
        for (int i = 0; i < n; i += len) {
            for (int j = 0; j < half; j++) {
                std::complex<float> w = tw[j * step];
                if (inverse) w = std::conj(w);
                std::complex<float> u = a[i + j], v = a[i + j + half] * w;
                a[i + j] = u + v;
                a[i + j + half] = u - v;
            }
        }
    }
}

void PConvSingle::Convolve(float *buffer) {
    ConvSegment(buffer, false, 0);
}

void PConvSingle::ConvolveInterleaved(float *buffer, int channel) {
    ConvSegment(buffer, true, channel);
}

void PConvSingle::ConvSegment(float *buffer, bool interleaved, int channel) {
    if (!this->instanceUsable || this->data == nullptr) return;
    PConvData &d = *this->data;
    const int B = this->segmentSize, N = d.fftSize;
    const int stride = interleaved ? 2 : 1;
    float *x = buffer + (interleaved ? channel : 0);

    // [previous block | this block] -> FFT, stored as the newest input.
    for (int i = 0; i < B; i++) {
        d.work[i] = d.history[i];
        d.work[B + i] = x[i * stride];
        d.history[i] = x[i * stride];
    }
    fft(d.work, false);
    d.ring = (d.ring + this->segmentCount - 1) % this->segmentCount;
    d.inputParts[d.ring] = d.work;

    std::fill(d.acc.begin(), d.acc.end(), std::complex<float>(0, 0));
    for (int p = 0; p < this->segmentCount; p++) {
        const auto &in = d.inputParts[(d.ring + p) % this->segmentCount];
        const auto &k = d.kernelParts[p];
        for (int i = 0; i < N; i++) d.acc[i] += in[i] * k[i];
    }
    fft(d.acc, true);
    const float scale = 1.0f / (float) N;
    for (int i = 0; i < B; i++) {
        x[i * stride] = d.acc[B + i].real() * scale;
    }
}

int PConvSingle::GetFFTSize() {
    return this->segmentSize * 2;
}

int PConvSingle::GetSegmentCount() {
    return this->segmentCount;
}

int PConvSingle::GetSegmentSize() {
    return this->segmentSize;
}

bool PConvSingle::InstanceUsable() {
    return this->instanceUsable;
}

int PConvSingle::LoadKernel(const float *kernel, int kernelSize, int segmentSize) {
    return LoadKernel(kernel, 1.0f, kernelSize, segmentSize);
}

int PConvSingle::LoadKernel(const float *kernel, float param_3, int kernelSize, int segmentSize) {
    if (kernel != nullptr && kernelSize >= 2 && segmentSize >= 2 && (segmentSize & (segmentSize - 1)) == 0) {
        this->instanceUsable = false;
        ReleaseResources();
        this->data = new PConvData();
        this->segmentSize = segmentSize;
        int n = ProcessKernel(kernel, param_3, kernelSize, 1);
        if (n != 0) {
            this->instanceUsable = true;
            return n;
        }
        ReleaseResources();
    }
    return 0;
}

int PConvSingle::ProcessKernel(const float *kernel, int kernelSize, int param_4) {
    return ProcessKernel(kernel, 1.0f, kernelSize, param_4);
}

// param_3 is the kernel's gain: VHE's values bring its kernels to about unity
// loudness.
int PConvSingle::ProcessKernel(const float *kernel, float param_3, int kernelSize, int param_5) {
    (void) param_5;
    if (this->data == nullptr || this->segmentSize <= 0) return 0;
    PConvData &d = *this->data;
    const int B = this->segmentSize, N = B * 2;
    d.fftSize = N;
    d.twiddles.resize(N / 2);
    for (int i = 0; i < N / 2; i++) {
        double a = -2.0 * M_PI * i / N;
        d.twiddles[i] = std::complex<float>((float) cos(a), (float) sin(a));
    }
    d.bitrev.resize(N);
    int bits = 0;
    while ((1 << bits) < N) bits++;
    for (int i = 0; i < N; i++) {
        int r = 0;
        for (int b = 0; b < bits; b++) if (i & (1 << b)) r |= 1 << (bits - 1 - b);
        d.bitrev[i] = r;
    }
    this->segmentCount = (kernelSize + B - 1) / B;
    d.kernelParts.assign(this->segmentCount, std::vector<std::complex<float>>(N));
    d.inputParts.assign(this->segmentCount, std::vector<std::complex<float>>(N));
    for (int p = 0; p < this->segmentCount; p++) {
        auto &part = d.kernelParts[p];
        for (int i = 0; i < B; i++) {
            int k = p * B + i;
            part[i] = std::complex<float>(k < kernelSize ? kernel[k] * param_3 : 0.0f, 0.0f);
        }
        fft(part, false);
    }
    d.history.assign(B, 0.0f);
    d.work.assign(N, std::complex<float>(0, 0));
    d.acc.assign(N, std::complex<float>(0, 0));
    d.ring = 0;
    return this->segmentCount;
}

void PConvSingle::ReleaseResources() {
    delete this->data;
    this->data = nullptr;
    this->instanceUsable = false;
    this->segmentCount = 0;
    this->segmentSize = 0;
}

void PConvSingle::Reset() {
    if (!this->instanceUsable || this->data == nullptr) return;
    std::fill(this->data->history.begin(), this->data->history.end(), 0.0f);
    for (auto &part : this->data->inputParts) {
        std::fill(part.begin(), part.end(), std::complex<float>(0, 0));
    }
}

void PConvSingle::UnloadKernel() {
    this->instanceUsable = false;
    ReleaseResources();
}
