#include "Backend.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QtEndian>
#include <cmath>

#include "PwEngine.h"
#include "ViperDsp.h"

#ifndef VIPERFX_VERSION
#define VIPERFX_VERSION "0.1"
#endif

namespace {
QString dataDir() {
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
}

// A WAV impulse response (PCM 16/24/32 or float, 1 or 2+ channels) as two
// channels at `rate` (linear resampling), at most 10 seconds.
bool readImpulse(const QString &path, uint32_t rate, std::vector<float> &l, std::vector<float> &r, QString *error) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) { *error = "can't open the file"; return false; }
    QByteArray d = f.read(64 * 1024 * 1024);
    auto u16 = [&](int o) { return qFromLittleEndian<quint16>(reinterpret_cast<const uchar *>(d.constData() + o)); };
    auto u32 = [&](int o) { return qFromLittleEndian<quint32>(reinterpret_cast<const uchar *>(d.constData() + o)); };
    if (d.size() < 44 || d.left(4) != "RIFF" || d.mid(8, 4) != "WAVE") { *error = "not a WAV file"; return false; }
    int pos = 12, fmtTag = 0, channels = 0, bits = 0;
    uint32_t srcRate = 0;
    const char *pcm = nullptr;
    qint64 pcmBytes = 0;
    while (pos + 8 <= d.size()) {
        QByteArray id = d.mid(pos, 4);
        qint64 size = u32(pos + 4);
        int body = pos + 8;
        if (id == "fmt " && size >= 16 && body + 16 <= d.size()) {
            fmtTag = u16(body);
            channels = u16(body + 2);
            srcRate = u32(body + 4);
            bits = u16(body + 14);
            if (fmtTag == 0xFFFE && size >= 26) fmtTag = u16(body + 24);  // WAVE_FORMAT_EXTENSIBLE
        } else if (id == "data") {
            pcm = d.constData() + body;
            pcmBytes = std::min<qint64>(size, d.size() - body);
            break;
        }
        pos = body + int(size + (size & 1));
    }
    if (!pcm || channels < 1 || srcRate == 0) { *error = "the WAV file has no sound in it"; return false; }
    bool isFloat = fmtTag == 3 && bits == 32;
    if (!(fmtTag == 1 && (bits == 16 || bits == 24 || bits == 32)) && !isFloat) {
        *error = "only 16, 24 or 32-bit PCM or 32-bit float WAV files"; return false;
    }
    int bps = bits / 8;
    qint64 frames = pcmBytes / (bps * channels);
    frames = std::min<qint64>(frames, qint64(srcRate) * 10);
    auto sample = [&](qint64 frame, int ch) -> float {
        const uchar *p = reinterpret_cast<const uchar *>(pcm + (frame * channels + ch) * bps);
        if (isFloat) { float v; memcpy(&v, p, 4); return v; }
        if (bits == 16) return qint16(qFromLittleEndian<quint16>(p)) / 32768.0f;
        if (bits == 24) { qint32 v = (p[0] | (p[1] << 8) | (p[2] << 16)); if (v & 0x800000) v |= ~0xFFFFFF; return v / 8388608.0f; }
        return qint32(qFromLittleEndian<quint32>(p)) / 2147483648.0f;
    };
    qint64 outFrames = frames * rate / srcRate;
    if (outFrames < 16) { *error = "the impulse response is too short"; return false; }
    l.resize(outFrames); r.resize(outFrames);
    for (qint64 i = 0; i < outFrames; i++) {
        double s = double(i) * srcRate / rate;
        qint64 a = qint64(s);
        double t = s - a;
        qint64 b = std::min(a + 1, frames - 1);
        int cr = channels > 1 ? 1 : 0;
        l[i] = float(sample(a, 0) * (1 - t) + sample(b, 0) * t);
        r[i] = float(sample(a, cr) * (1 - t) + sample(b, cr) * t);
    }
    return true;
}
}  // namespace

Backend::Backend(QObject *parent)
    : QObject(parent),
      settings(QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation) + "/viperfx.conf", QSettings::IniFormat) {
    currentProfile = settings.value("general/profile", "headphone").toString();
    if (currentProfile != "headphone" && currentProfile != "speaker") currentProfile = "headphone";
    powerOn = settings.value("general/power", true).toBool();
    keep = settings.value("general/keepRunning", true).toBool();
    QDir().mkpath(presetFolder());
    connect(&meterTimer, &QTimer::timeout, this, &Backend::pollEngine);
    meterTimer.start(50);
}

Backend::~Backend() { stopEngine(); }

void Backend::startEngine() {
    engine = std::make_unique<PwEngine>();
    std::string err;
    if (!engine->start(&err)) {
        engineError = QString::fromStdString(err);
        engine.reset();
    } else {
        engineError.clear();
        applyAll();
    }
    emit statusChanged();
}

void Backend::stopEngine() {
    if (engine) engine->stop();
    engine.reset();
}

QVariantMap Backend::defaults(const QString &profile) {
    QVariantMap m;
    for (const std::string &k : ViperDsp::keys()) m[QString::fromStdString(k)] = 0;
    m.remove("master.enable");
    m["master.volume"] = 100; m["master.pan"] = 0; m["master.limit"] = 100;
    m["agc.ratio"] = 100; m["agc.volume"] = 100; m["agc.maxgain"] = 300;
    m["spectrum.strength"] = 10;
    m["field.widen"] = 100; m["field.mid"] = 100; m["field.depth"] = 200;
    m["diff.delay"] = 400;
    m["vhe.level"] = 0;
    m["reverb.room"] = 30; m["reverb.width"] = 50; m["reverb.damp"] = 50; m["reverb.wet"] = 20; m["reverb.dry"] = 80;
    m["dynsys.xlow"] = 100; m["dynsys.xhigh"] = 5600; m["dynsys.ylow"] = 40; m["dynsys.yhigh"] = 80;
    m["dynsys.sidex"] = 50; m["dynsys.sidey"] = 50; m["dynsys.strength"] = 50; m["dynsys.device"] = 4;
    m["bass.mode"] = 0; m["bass.freq"] = 76; m["bass.gain"] = 100;
    m["clarity.mode"] = 0; m["clarity.gain"] = 100;
    m["cure.level"] = 0; m["analogx.level"] = 0;
    m["eq.preset"] = 0;
    Q_UNUSED(profile);
    return m;
}

int Backend::get(const QString &key) const {
    QVariant d = defaults(currentProfile).value(key, 0);
    return settings.value(settingsKey(key), d).toInt();
}

void Backend::push(const QString &key, int value) {
    if (!engine) return;
    std::string k = key.toStdString();
    engine->post([k, value](ViperDsp &d) { d.set(k, value); });
}

void Backend::set(const QString &key, int value) {
    if (settings.value(settingsKey(key)).toInt() == value && settings.contains(settingsKey(key))) return;
    settings.setValue(settingsKey(key), value);
    push(key, value);
    rev++;
    emit revisionChanged();
}

void Backend::setMany(const QVariantMap &values) {
    for (auto it = values.begin(); it != values.end(); ++it) {
        settings.setValue(settingsKey(it.key()), it.value().toInt());
        push(it.key(), it.value().toInt());
    }
    rev++;
    emit revisionChanged();
}

void Backend::resetProfile() {
    settings.remove(currentProfile);
    applyAll();
    rev++;
    emit revisionChanged();
    emit filesChanged();
}

void Backend::applyAll() {
    if (!engine) return;
    QVariantMap d = defaults(currentProfile);
    for (const std::string &k : ViperDsp::keys()) {
        QString key = QString::fromStdString(k);
        if (key == "master.enable") continue;
        push(key, get(key));
    }
    push("master.enable", powerOn ? 1 : 0);
    QString err;
    QString ddc = settings.value(settingsKey("ddc.file")).toString();
    if (!ddc.isEmpty()) applyDdcFile(ddc, &err);
    else engine->post([](ViperDsp &x) { x.setDdc({}, {}); x.set("ddc.enable", 0); });
    QString conv = settings.value(settingsKey("conv.file")).toString();
    if (!conv.isEmpty()) applyConvolverFile(conv, &err);
    else engine->post([](ViperDsp &x) { x.setConvolver({}, {}); });
    if (get("ddc.enable") && !ddc.isEmpty()) push("ddc.enable", 1);
    if (get("conv.enable") && !conv.isEmpty()) push("conv.enable", 1);
    fileErr = err;
}

void Backend::setPower(bool on) {
    if (powerOn == on) return;
    powerOn = on;
    settings.setValue("general/power", on);
    push("master.enable", on ? 1 : 0);
    emit powerChanged();
}

void Backend::setProfile(const QString &p) {
    if (p == currentProfile || (p != "headphone" && p != "speaker")) return;
    currentProfile = p;
    settings.setValue("general/profile", p);
    applyAll();
    rev++;
    emit profileChanged();
    emit revisionChanged();
    emit filesChanged();
}

void Backend::setKeepRunning(bool k) {
    if (keep == k) return;
    keep = k;
    settings.setValue("general/keepRunning", k);
    emit keepRunningChanged();
}

bool Backend::connected() const { return engine && engine->running(); }
bool Backend::flowing() const { return engine && engine->flowing(); }
QString Backend::output() const { return engine ? QString::fromStdString(engine->outputName()) : QString(); }

QString Backend::status() const {
    if (!engine) return engineError.isEmpty() ? QStringLiteral("Not started") : engineError;
    QString p = QString::fromStdString(engine->problem());
    if (!p.isEmpty()) return p;
    QString out = output();
    if (out == "phone") out = "Phone";
    if (out.isEmpty()) return QStringLiteral("No speaker to play into");
    return engine->flowing() ? QStringLiteral("Processing  ·  ViPER FX → %1").arg(out)
                             : QStringLiteral("Ready  ·  ViPER FX → %1  ·  nothing playing").arg(out);
}

void Backend::pollEngine() {
    if (!engine) return;
    float il, ir, ol, orr;
    engine->takePeaks(il, ir, ol, orr);
    // Meters fall back slowly, like a VU.
    auto fall = [](double cur, double v) { return v > cur ? v : cur * 0.85; };
    mInL = fall(mInL, il); mInR = fall(mInR, ir); mOutL = fall(mOutL, ol); mOutR = fall(mOutR, orr);
    emit metersChanged();
    bool f = engine->flowing();
    QString o = output();
    if (f != lastFlowing || o != lastOutput) {
        lastFlowing = f; lastOutput = o;
        emit statusChanged();
    }
}

QString Backend::ddcName() const {
    return QFileInfo(settings.value(settingsKey("ddc.file")).toString()).completeBaseName();
}

QString Backend::convName() const {
    return QFileInfo(settings.value(settingsKey("conv.file")).toString()).completeBaseName();
}

bool Backend::applyDdcFile(const QString &path, QString *error) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) { *error = "ViPER-DDC: can't open " + QFileInfo(path).fileName(); return false; }
    std::vector<float> a, b;
    std::string err;
    if (!ViperDsp::parseVdc(f.readAll().toStdString(), a, b, &err)) {
        *error = "ViPER-DDC: " + QString::fromStdString(err);
        return false;
    }
    if (engine) engine->post([a, b](ViperDsp &x) { x.setDdc(a, b); });
    return true;
}

bool Backend::loadDdc(const QUrl &file) {
    QString path = file.isLocalFile() ? file.toLocalFile() : file.toString();
    // Keep a copy, so the effect works after the original moves.
    QString dir = dataDir() + "/ddc";
    QDir().mkpath(dir);
    QString copy = dir + "/" + QFileInfo(path).fileName();
    if (QFileInfo(path).absoluteFilePath() != QFileInfo(copy).absoluteFilePath()) {
        QFile::remove(copy);
        QFile::copy(path, copy);
    }
    QString err;
    bool ok = applyDdcFile(QFile::exists(copy) ? copy : path, &err);
    fileErr = err;
    if (ok) {
        settings.setValue(settingsKey("ddc.file"), QFile::exists(copy) ? copy : path);
        set("ddc.enable", 1);
        rev++;
        emit revisionChanged();
    }
    emit filesChanged();
    return ok;
}

void Backend::clearDdc() {
    settings.remove(settingsKey("ddc.file"));
    set("ddc.enable", 0);
    if (engine) engine->post([](ViperDsp &x) { x.setDdc({}, {}); });
    fileErr.clear();
    rev++;
    emit revisionChanged();
    emit filesChanged();
}

bool Backend::applyConvolverFile(const QString &path, QString *error) {
    std::vector<float> l, r;
    QString err;
    if (!readImpulse(path, 48000, l, r, &err)) {
        *error = "Convolver: " + err;
        return false;
    }
    if (engine) engine->post([l, r](ViperDsp &x) { x.setConvolver(l, r); });
    return true;
}

bool Backend::loadConvolver(const QUrl &file) {
    QString path = file.isLocalFile() ? file.toLocalFile() : file.toString();
    QString dir = dataDir() + "/kernel";
    QDir().mkpath(dir);
    QString copy = dir + "/" + QFileInfo(path).fileName();
    if (QFileInfo(path).absoluteFilePath() != QFileInfo(copy).absoluteFilePath()) {
        QFile::remove(copy);
        QFile::copy(path, copy);
    }
    QString use = QFile::exists(copy) ? copy : path;
    QString err;
    bool ok = applyConvolverFile(use, &err);
    fileErr = err;
    if (ok) {
        settings.setValue(settingsKey("conv.file"), use);
        settings.setValue(settingsKey("conv.enable"), 1);
        push("conv.enable", 1);
        rev++;
        emit revisionChanged();
    }
    emit filesChanged();
    return ok;
}

void Backend::clearConvolver() {
    settings.remove(settingsKey("conv.file"));
    set("conv.enable", 0);
    if (engine) engine->post([](ViperDsp &x) { x.setConvolver({}, {}); });
    fileErr.clear();
    rev++;
    emit revisionChanged();
    emit filesChanged();
}

QString Backend::presetFolder() const { return dataDir() + "/presets"; }

QStringList Backend::presets() const {
    QStringList out;
    for (const QFileInfo &fi : QDir(presetFolder()).entryInfoList({"*.json"}, QDir::Files, QDir::Name | QDir::IgnoreCase))
        out << fi.completeBaseName();
    return out;
}

bool Backend::savePreset(const QString &name) {
    QString clean = name.trimmed();
    clean.replace('/', '-');
    if (clean.isEmpty()) return false;
    QJsonObject o;
    QVariantMap d = defaults(currentProfile);
    for (auto it = d.begin(); it != d.end(); ++it) o[it.key()] = get(it.key());
    for (const char *f : {"ddc.file", "conv.file"}) {
        QString v = settings.value(settingsKey(f)).toString();
        if (!v.isEmpty()) o[f] = v;
    }
    QFile file(presetFolder() + "/" + clean + ".json");
    if (!file.open(QIODevice::WriteOnly)) return false;
    file.write(QJsonDocument(o).toJson());
    emit presetsChanged();
    return true;
}

bool Backend::loadPreset(const QString &name) {
    QFile file(presetFolder() + "/" + name + ".json");
    if (!file.open(QIODevice::ReadOnly)) return false;
    QJsonObject o = QJsonDocument::fromJson(file.readAll()).object();
    if (o.isEmpty()) return false;
    settings.remove(currentProfile);
    for (auto it = o.begin(); it != o.end(); ++it) {
        if (it.key().endsWith(".file")) settings.setValue(settingsKey(it.key()), it.value().toString());
        else settings.setValue(settingsKey(it.key()), it.value().toInt());
    }
    applyAll();
    rev++;
    emit revisionChanged();
    emit filesChanged();
    return true;
}

void Backend::deletePreset(const QString &name) {
    QFile::remove(presetFolder() + "/" + name + ".json");
    emit presetsChanged();
}

QString Backend::version() const { return QStringLiteral(VIPERFX_VERSION); }
