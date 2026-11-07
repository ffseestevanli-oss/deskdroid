// DeskDroid's Steam Installation Assistant: the QML pages' link to
// deskdroid-steam (app/src/main/assets/x86), which does the work.
#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QVariantList>

class Backend : public QObject
{
    Q_OBJECT
    // What is on the phone, from `deskdroid-steam --status`.
    Q_PROPERTY(bool fexReady READ fexReady NOTIFY statusChanged)
    Q_PROPERTY(bool steamReady READ steamReady NOTIFY statusChanged)
    // "Continue without Steam" was chosen (until a purge).
    Q_PROPERTY(bool skipped READ skipped WRITE setSkipped NOTIFY statusChanged)
    // The tools page has been seen since Steam was installed ("Welcome back!").
    Q_PROPERTY(bool welcomedBack READ welcomedBack WRITE setWelcomedBack NOTIFY statusChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // Where FEX downloads from (~/.config/deskdroid-fex-url), empty = the default.
    Q_PROPERTY(QString fexSource READ fexSource WRITE setFexSource NOTIFY fexSourceChanged)
    Q_PROPERTY(QString defaultFexSource READ defaultFexSource CONSTANT)
    // A FEX .zip on the phone to install from (~/.config/deskdroid-fex-zip), empty = none.
    Q_PROPERTY(QString fexZip READ fexZip WRITE setFexZip NOTIFY fexSourceChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    bool fexReady() const { return m_fex; }
    bool steamReady() const { return m_steam; }
    bool skipped() const;
    void setSkipped(bool on);
    bool welcomedBack() const;
    void setWelcomedBack(bool on);
    bool busy() const { return m_proc && m_proc->state() != QProcess::NotRunning; }
    QString fexSource() const;
    void setFexSource(const QString &url);
    QString defaultFexSource() const;
    QString fexZip() const;
    void setFexZip(const QString &path);

    Q_INVOKABLE void refresh();
    // Sets up FEX-Emu, the x86 system and Steam: line(), progress(), finished().
    Q_INVOKABLE void install();
    // update | soft-reset | hard-reset | uninstall | purge
    Q_INVOKABLE void runTool(const QString &name);
    Q_INVOKABLE void cancel();

    Q_INVOKABLE void launchSteam(const QString &url = QString());
    Q_INVOKABLE void runX86(const QString &file);
    Q_INVOKABLE void runWindows(const QString &file);
    Q_INVOKABLE void wineTool(const QString &tool, const QString &prefix = QString());
    Q_INVOKABLE void openFolder(const QString &path);
    Q_INVOKABLE bool removeFolder(const QString &path);
    Q_INVOKABLE QString localPath(const QString &url) const;

    // {name, path, appid, kind ("steam"|"deskdroid"), size}
    Q_INVOKABLE QVariantList prefixes() const;
    // {appid, name, size} for each game in Steam's library
    Q_INVOKABLE QVariantList games() const;
    Q_INVOKABLE bool hasProton() const;
    Q_INVOKABLE QString logTail(const QString &which, int lines = 40) const;
    Q_INVOKABLE QString steamDir() const;

Q_SIGNALS:
    void statusChanged();
    void busyChanged();
    void fexSourceChanged();
    void line(const QString &text);
    // fraction 0..1 (or -1: no estimate), label: the step being done
    void progress(double fraction, const QString &label);
    void finished(bool ok, const QString &message);

private:
    QString script() const;
    QString configFile(const QString &name) const;
    void start(const QStringList &args, bool install);
    void onLine(const QString &text);
    void detached(const QStringList &args);

    QProcess *m_proc = nullptr;
    QByteArray m_pending;
    bool m_fex = false;
    bool m_steam = false;
    bool m_installing = false;
    int m_stage = 0;
    int m_lastMeter = -10;
    QString m_lastLine;
};
