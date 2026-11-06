// DeskDroid: stand-in for libnotificationmanager's JobsModel. The task
// manager only creates it (to show file copy progress on launchers); no
// jobs are reported here yet.
#pragma once

#include <QSharedPointer>

namespace NotificationManager
{
class JobsModel
{
public:
    using Ptr = QSharedPointer<JobsModel>;
    static Ptr createJobsModel()
    {
        return Ptr(new JobsModel);
    }
    void init()
    {
    }
};
}
