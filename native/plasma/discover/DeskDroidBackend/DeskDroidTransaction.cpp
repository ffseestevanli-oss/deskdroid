/*
 *   SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#include "DeskDroidTransaction.h"
#include "DeskDroidBackend.h"
#include "DeskDroidResource.h"

#include <QRegularExpression>

using namespace Qt::StringLiterals;

DeskDroidTransaction::DeskDroidTransaction(DeskDroidResource *app, Role role)
    : Transaction(app->backend(), app, role, {})
    , m_app(app)
    , m_process(new QProcess(this))
    , m_update(role == InstallRole && app->state() == AbstractResource::Upgradeable)
{
    setCancellable(true);
    setStatus(QueuedStatus);

    QStringList args;
    if (role == RemoveRole) {
        args = {u"uninstall"_s, u"--user"_s, u"-y"_s, app->ref()};
    } else if (m_update) {
        args = {u"update"_s, u"--user"_s, u"-y"_s, app->ref()};
    } else {
        args = {u"install"_s, u"--user"_s, u"-y"_s, u"flathub"_s, app->ref()};
    }
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_process, &QProcess::readyRead, this, &DeskDroidTransaction::readOutput);
    connect(m_process, &QProcess::finished, this, &DeskDroidTransaction::finished);
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart) {
            Q_EMIT passiveMessage(m_process->program() + u": "_s + m_process->errorString());
            setStatus(DoneWithErrorStatus);
            deleteLater();
        }
    });
    static_cast<DeskDroidBackend *>(app->backend())->startFlatpak(m_process, args);
    setStatus(role == RemoveRole ? CommittingStatus : DownloadingStatus);
}

// With -y (not --noninteractive, which prints no progress at all) flatpak
// prints "Installing 1/3… 45%  1.2 MB/s" lines, also when not on a terminal.
void DeskDroidTransaction::readOutput()
{
    m_buffer += m_process->readAll();
    static const QRegularExpression step(u"(\\d+)/(\\d+)"_s);
    static const QRegularExpression percent(u"(\\d{1,3})%"_s);
    int cut;
    while ((cut = qMax(m_buffer.lastIndexOf('\n'), m_buffer.lastIndexOf('\r'))) >= 0) {
        const QString text = QString::fromUtf8(m_buffer.left(cut));
        m_buffer.remove(0, cut + 1);
        const auto lines = text.split(QRegularExpression(u"[\r\n]"_s), Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            m_lastLines = QString(m_lastLines + u"\n"_s + line).right(600);
            int n = 1, total = 1;
            if (const auto m = step.match(line); m.hasMatch()) {
                n = m.captured(1).toInt();
                total = qMax(1, m.captured(2).toInt());
            }
            const auto pm = percent.match(line);
            if (pm.hasMatch()) {
                const int p = qBound(0, pm.captured(1).toInt(), 100);
                setProgress(qBound(0, ((n - 1) * 100 + p) / total, 100));
            }
        }
    }
}

void DeskDroidTransaction::finished(int code, QProcess::ExitStatus exitStatus)
{
    readOutput();
    auto backend = m_app ? static_cast<DeskDroidBackend *>(m_app->backend()) : nullptr;
    if (status() == CancelledStatus) {
        // cancel() already set it
    } else if (exitStatus != QProcess::NormalExit || code != 0) {
        Q_EMIT passiveMessage(m_lastLines.trimmed().section(u'\n', -3));
        setStatus(DoneWithErrorStatus);
    } else {
        if (m_app) {
            m_app->setState(role() == RemoveRole ? AbstractResource::None : AbstractResource::Installed);
        }
        setProgress(100);
        setStatus(DoneStatus);
    }
    if (backend) {
        backend->refreshInstalled();
    }
    deleteLater();
}

void DeskDroidTransaction::cancel()
{
    setStatus(CancelledStatus);
    m_process->terminate();
}

#include "moc_DeskDroidTransaction.cpp"
