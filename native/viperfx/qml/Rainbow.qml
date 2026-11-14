import QtQuick

// The rainbow line DD Party puts on active things.
Rectangle {
    implicitHeight: 2
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Theme.rainbow[0] }
        GradientStop { position: 0.17; color: Theme.rainbow[1] }
        GradientStop { position: 0.33; color: Theme.rainbow[2] }
        GradientStop { position: 0.5; color: Theme.rainbow[3] }
        GradientStop { position: 0.67; color: Theme.rainbow[4] }
        GradientStop { position: 0.83; color: Theme.rainbow[5] }
        GradientStop { position: 1.0; color: Theme.rainbow[6] }
    }
}
