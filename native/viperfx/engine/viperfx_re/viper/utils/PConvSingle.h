#pragma once

// Uniformly partitioned FFT convolution (overlap-save) of one channel, in
// blocks of segmentSize samples. ViPERFX_RE left this class as a stub, so
// Headphone Surround+ and the convolver did nothing; DeskDroid's ViPER FX
// fills it in (native/viperfx/README.md).

#include <complex>
#include <vector>

class PConvSingle {
    struct PConvData {
        int fftSize = 0;
        std::vector<std::complex<float>> twiddles;
        std::vector<int> bitrev;
        std::vector<std::vector<std::complex<float>>> kernelParts;  // FFTs of the kernel's partitions
        std::vector<std::vector<std::complex<float>>> inputParts;   // FFTs of the last inputs (a ring)
        int ring = 0;
        std::vector<float> history;  // the previous block (overlap-save)
        std::vector<std::complex<float>> work, acc;
    };
public:
    PConvSingle();
    PConvSingle(const PConvSingle &) = delete;
    PConvSingle &operator=(const PConvSingle &) = delete;

    ~PConvSingle();

    void Reset();

    int GetFFTSize();

    int GetSegmentCount();

    int GetSegmentSize();

    bool InstanceUsable();

    void Convolve(float *buffer);

    void ConvolveInterleaved(float *buffer, int channel);

    void ConvSegment(float *buffer, bool interleaved, int channel);

    int LoadKernel(const float *kernel, int kernelSize, int segmentSize);

    int LoadKernel(const float *kernel, float param_3, int kernelSize, int segmentSize);

    int ProcessKernel(const float *kernel, int kernelSize, int param_4);

    int ProcessKernel(const float *kernel, float param_3, int kernelSize, int param_5);

    void ReleaseResources();

    void UnloadKernel();

    bool instanceUsable;
    int segmentCount;
    int segmentSize;
    PConvData *data;

private:
    void fft(std::vector<std::complex<float>> &a, bool inverse);
};
