/*
 *   DeskDroid: an install, update or removal, run by the flatpak command.
 *   SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
#pragma once

#include <QPointer>
#include <QProcess>
#include <Transaction/Transaction.h>

class DeskDroidResource;

class DeskDroidTransaction : public Transaction
{
    Q_OBJECT
public:
    DeskDroidTransaction(DeskDroidResource *app, Role role);
    void cancel() override;

private:
    void readOutput();
    void finished(int code, QProcess::ExitStatus exitStatus);

    QPointer<DeskDroidResource> m_app;
    QProcess *m_process;
    QByteArray m_buffer;
    QString m_lastLines;
    bool m_update;
};
