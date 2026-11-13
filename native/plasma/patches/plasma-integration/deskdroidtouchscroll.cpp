/*
    DeskDroid: finger scrolling for Qt Widgets apps.

    With Direct touch, the phone's touches reach apps as real Wayland touch
    events. QtQuick (Plasma, Kirigami, System Settings), GTK, Firefox and
    Chromium scroll with the finger by themselves; Qt Widgets don't: a
    QScrollArea or list turns a touch into a mouse press and a drag, which
    selects instead of scrolling. Every scroll area gets a QScroller for touch
    when it is polished, as KDE's touch-aware apps (Dolphin) do themselves:
    the content follows the finger 1:1 and keeps going with a flick, a tap
    still clicks, and a mouse or touchpad is unaffected (touch gesture only).

    SPDX-License-Identifier: LGPL-2.0-or-later
*/
#include <QAbstractScrollArea>
#include <QCoreApplication>
#include <QEvent>
#include <QScroller>
#include <QScrollerProperties>

namespace
{
class DeskDroidTouchScroll : public QObject
{
public:
    using QObject::QObject;

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::Polish) {
            if (auto *area = qobject_cast<QAbstractScrollArea *>(watched)) {
                QWidget *viewport = area->viewport();
                // An app that set up its own (Dolphin) keeps it.
                if (viewport && !QScroller::hasScroller(viewport) && !viewport->property("_deskdroid_touch").toBool()) {
                    viewport->setProperty("_deskdroid_touch", true);
                    QScroller::grabGesture(viewport, QScroller::TouchGesture);
                    QScrollerProperties p = QScroller::scroller(viewport)->scrollerProperties();
                    // Like a phone: no rubber band past the ends, a short wait
                    // before a press counts so a scroll doesn't click first.
                    p.setScrollMetric(QScrollerProperties::HorizontalOvershootPolicy, QVariant::fromValue(QScrollerProperties::OvershootAlwaysOff));
                    p.setScrollMetric(QScrollerProperties::VerticalOvershootPolicy, QVariant::fromValue(QScrollerProperties::OvershootAlwaysOff));
                    p.setScrollMetric(QScrollerProperties::MousePressEventDelay, 0.1);
                    QScroller::scroller(viewport)->setScrollerProperties(p);
                }
            }
        }
        return QObject::eventFilter(watched, event);
    }
};
}

void deskdroidInstallTouchScroll()
{
    // Called while the application is still being made (the platform theme
    // comes first), so no telling QApplication from QGuiApplication yet: a
    // QtQuick-only app simply never polishes a scroll area.
    if (qEnvironmentVariableIsSet("DESKDROID_NO_TOUCH_SCROLL") || !QCoreApplication::instance()) {
        return;
    }
    QCoreApplication::instance()->installEventFilter(new DeskDroidTouchScroll(QCoreApplication::instance()));
}
