// Backend: the app's settings (one set per output profile, like
// ViPER4Android's headphone and speaker modes), presets, effect files, and
// the PipeWire engine they drive. QML reads and writes it.
#pragma once

#include <QObject>
#include <QSettings>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <memory>

class PwEngine;

class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool power READ power WRITE setPower NOTIFY powerChanged)
    Q_PROPERTY(QString profile READ profile WRITE setProfile NOTIFY profileChanged)
    Q_PROPERTY(bool keepRunning READ keepRunning WRITE setKeepRunning NOTIFY keepRunningChanged)
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY statusChanged)
    Q_PROPERTY(bool flowing READ flowing NOTIFY statusChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString output READ output NOTIFY statusChanged)
    Q_PROPERTY(double inL READ inL NOTIFY metersChanged)
    Q_PROPERTY(double inR READ inR NOTIFY metersChanged)
    Q_PROPERTY(double outL READ outL NOTIFY metersChanged)
    Q_PROPERTY(double outR READ outR NOTIFY metersChanged)
    Q_PROPERTY(QString ddcName READ ddcName NOTIFY filesChanged)
    Q_PROPERTY(QString convName READ convName NOTIFY filesChanged)
    Q_PROPERTY(QString fileError READ fileError NOTIFY filesChanged)
    Q_PROPERTY(QStringList presets READ presets NOTIFY presetsChanged)
    Q_PROPERTY(QString version READ version CONSTANT)

public:
    explicit Backend(QObject *parent = nullptr);
    ~Backend() override;

    void startEngine();
    void stopEngine();

    bool power() const { return powerOn; }
    void setPower(bool on);
    QString profile() const { return currentProfile; }
    void setProfile(const QString &p);
    bool keepRunning() const { return keep; }
    void setKeepRunning(bool k);
    int revision() const { return rev; }
    bool connected() const;
    bool flowing() const;
    QString status() const;
    QString output() const;
    double inL() const { return mInL; }
    double inR() const { return mInR; }
    double outL() const { return mOutL; }
    double outR() const { return mOutR; }
    QString ddcName() const;
    QString convName() const;
    QString fileError() const { return fileErr; }
    QStringList presets() const;
    QString version() const;

    Q_INVOKABLE int get(const QString &key) const;
    Q_INVOKABLE void set(const QString &key, int value);
    Q_INVOKABLE void setMany(const QVariantMap &values);
    Q_INVOKABLE void resetProfile();
    Q_INVOKABLE bool loadDdc(const QUrl &file);
    Q_INVOKABLE void clearDdc();
    Q_INVOKABLE bool loadConvolver(const QUrl &file);
    Q_INVOKABLE void clearConvolver();
    Q_INVOKABLE bool savePreset(const QString &name);
    Q_INVOKABLE bool loadPreset(const QString &name);
    Q_INVOKABLE void deletePreset(const QString &name);
    Q_INVOKABLE QString presetFolder() const;

    static QVariantMap defaults(const QString &profile);

signals:
    void powerChanged();
    void profileChanged();
    void keepRunningChanged();
    void revisionChanged();
    void statusChanged();
    void metersChanged();
    void filesChanged();
    void presetsChanged();
    void showRequested();

private:
    void applyAll();
    void push(const QString &key, int value);
    bool applyDdcFile(const QString &path, QString *error);
    bool applyConvolverFile(const QString &path, QString *error);
    void pollEngine();
    QString settingsKey(const QString &key) const { return currentProfile + "/" + key; }

    std::unique_ptr<PwEngine> engine;
    QSettings settings;
    QString currentProfile = "headphone";
    bool powerOn = true;
    bool keep = true;
    int rev = 0;
    QString engineError;
    QString fileErr;
    QTimer meterTimer;
    double mInL = 0, mInR = 0, mOutL = 0, mOutR = 0;
    bool lastFlowing = false;
    QString lastOutput;
};
