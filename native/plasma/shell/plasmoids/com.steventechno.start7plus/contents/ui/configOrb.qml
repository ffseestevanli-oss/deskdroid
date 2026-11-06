import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_orbMode: "orb"
    property string cfg_orbModeDefault: "orb"
    property string cfg_orbShapeType: "circle"
    property string cfg_orbShapeTypeDefault: "circle"
    property int cfg_buttonSize: 132
    property string cfg_buttonAlign: "left"
    property string cfg_buttonAlignDefault: "left"
    property int cfg_buttonOffsetX: -5
    property int cfg_buttonOffsetXDefault: -5
    property int cfg_buttonOffsetY: 0
    property int cfg_buttonOffsetYDefault: 0
    property bool cfg_sizeUnlocked: false
    property bool cfg_sizeUnlockedDefault: false
    property int cfg_xpButtonSize: 132
    property int cfg_xpButtonSizeDefault: 132
    property int cfg_buttonSizeDefault: 132
    property string cfg_orbStyle: "glossy"
    property string cfg_orbStyleDefault: "glossy"
    property string cfg_orbImage: ""
    property string cfg_orbImageDefault: ""
    property bool cfg_orbThreeState: false
    property bool cfg_orbThreeStateDefault: false
    property int cfg_orbSize: 115
    property int cfg_orbSizeDefault: 115
    property int cfg_orbOffsetX: 0
    property int cfg_orbOffsetXDefault: 0
    property int cfg_orbOffsetY: 0
    property int cfg_orbOffsetYDefault: 0
    property int cfg_orbRotation: 0
    property int cfg_orbRotationDefault: 0
    property int cfg_orbOpacity: 100
    property int cfg_orbOpacityDefault: 100
    property bool cfg_orbFlip: false
    property bool cfg_orbFlipDefault: false
    property string cfg_orbColor: "#2f86d0"
    property string cfg_orbColorDefault: "#2f86d0"
    property bool cfg_orbGlass: true
    property bool cfg_orbGlassDefault: true
    property string cfg_orbLogoMode: "icon"
    property string cfg_orbLogoModeDefault: "icon"
    property string cfg_orbLogoImage: ""
    property string cfg_orbLogoImageDefault: ""
    property string cfg_orbLogoColor: ""
    property string cfg_orbLogoColorDefault: ""
    property string cfg_orbTintColor: "#ffffff"
    property string cfg_orbTintColorDefault: "#ffffff"
    property int cfg_orbTintStrength: 0
    property int cfg_orbTintStrengthDefault: 0
    property int cfg_orbBrightness: 0
    property int cfg_orbBrightnessDefault: 0
    property int cfg_orbContrast: 0
    property int cfg_orbContrastDefault: 0
    property int cfg_orbSaturation: 0
    property int cfg_orbSaturationDefault: 0
    property bool cfg_orbHoverGlow: true
    property bool cfg_orbHoverGlowDefault: true
    property bool cfg_orbPressAnim: true
    property bool cfg_orbPressAnimDefault: true
    property string cfg_orbLogoAlign: "center"
    property string cfg_orbLogoAlignDefault: "center"
    property bool cfg_orbLengthOn: false
    property bool cfg_orbLengthOnDefault: false
    property int cfg_orbLength: 90
    property int cfg_orbLengthDefault: 90
    property int cfg_orbRainbowSpeed: 8
    property int cfg_orbRainbowSpeedDefault: 8
    property bool cfg_orbRainbow: true
    property bool cfg_orbRainbowDefault: true
    property string cfg_orbColorMode: "accent"
    property string cfg_orbColorModeDefault: "accent"
    property string cfg_orbGradColor1: "#ff3d81"
    property string cfg_orbGradColor1Default: "#ff3d81"
    property string cfg_orbGradColor2: "#3d8bff"
    property string cfg_orbGradColor2Default: "#3d8bff"
    property string cfg_orbGradColor3: "#3dffb0"
    property string cfg_orbGradColor3Default: "#3dffb0"
    property int cfg_orbWaveSpacing: 100
    property int cfg_orbWaveSpacingDefault: 100
    property bool cfg_orbGradThree: false
    property bool cfg_orbGradThreeDefault: false
    property string cfg_buttonStyle: "classic"
    property string cfg_buttonStyleDefault: "classic"
    property string cfg_buttonText: "Start"
    property string cfg_buttonTextDefault: "Start"
    property int cfg_buttonLength: 90
    property int cfg_buttonLengthDefault: 90
    property string cfg_classicButtonColor: ""
    property string cfg_classicButtonColorDefault: ""
    property string cfg_buttonColor: "#3a9a3a"
    property string cfg_buttonColorDefault: "#3a9a3a"

    // stretch applies to the built-in shapes only
    readonly property bool previewStretch: page.cfg_orbMode !== "button" && page.cfg_orbStyle !== "custom" && page.cfg_orbLengthOn
    readonly property real previewLength: previewStretch ? page.cfg_orbLength : 64

    QQC2.ButtonGroup { id: modeGroup }

    ColorDialog {
        id: colorPicker
        property string key: ""
        title: i18n("Choose a color")
        onAccepted: page["cfg_" + key] = selectedColor.toString()
    }

    FileDialog {
        id: imagePicker
        property string target: "orbImage"
        title: i18n("Choose an image")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.bmp *.webp *.gif *.svg)")]
        onAccepted: {
            page["cfg_" + target] = selectedFile.toString()
            if (target === "orbImage") page.cfg_orbStyle = "custom"
            if (target === "orbLogoImage") page.cfg_orbLogoMode = "image"
        }
    }

    // The preview lives in its own frame above the scrolling options, so it is always visible.
    header: Rectangle {
        implicitHeight: headerCol.implicitHeight + Kirigami.Units.largeSpacing * 2
        color: Kirigami.Theme.alternateBackgroundColor
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false
        border.width: 1
        border.color: Kirigami.Theme.disabledTextColor

        ColumnLayout {
            id: headerCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.max(Kirigami.Units.gridUnit * 8, (page.cfg_orbMode === "button" ? page.cfg_buttonLength : page.previewLength) + 40)
                Layout.preferredHeight: 76
                radius: 4
                color: Kirigami.Theme.backgroundColor
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                clip: true

                OrbVisual {
                    anchors.centerIn: parent
                    width: page.cfg_orbMode === "button" ? page.cfg_buttonLength : page.previewLength
                    height: page.cfg_orbMode === "button" ? 32 : 64
                    mode: page.cfg_orbMode
                    style: page.cfg_orbStyle
                    shapeKind: page.cfg_orbShapeType
                    buttonSizeFraction: (page.cfg_buttonStyle === "xp" ? page.cfg_xpButtonSize : page.cfg_buttonSize) / 100
                    buttonAlign: page.cfg_buttonAlign
                    buttonOffsetX: page.cfg_buttonOffsetX
                    buttonOffsetY: page.cfg_buttonOffsetY
                    imageSource: page.cfg_orbImage
                    threeState: page.cfg_orbThreeState
                    sizeFraction: page.cfg_orbSize / 100
                    offsetX: page.cfg_orbOffsetX
                    offsetY: page.cfg_orbOffsetY
                    orbRotation: page.cfg_orbRotation
                    orbOpacity: page.cfg_orbOpacity / 100
                    flipped: page.cfg_orbFlip
                    baseColor: page.cfg_orbColor
                    glass: page.cfg_orbGlass
                    logoMode: page.cfg_orbLogoMode
                    logoImage: page.cfg_orbLogoImage
                    logoColor: page.cfg_orbLogoColor
                    tintColor: page.cfg_orbTintColor
                    tintStrength: page.cfg_orbTintStrength / 100
                    brightness: page.cfg_orbBrightness / 100
                    contrast: page.cfg_orbContrast / 100
                    saturation: page.cfg_orbSaturation / 100
                    hoverGlow: page.cfg_orbHoverGlow
                    pressAnimation: page.cfg_orbPressAnim
                    rainbow: page.cfg_orbRainbow
                    rainbowSpeed: page.cfg_orbRainbowSpeed
                    colorMode: page.cfg_orbColorMode
                    gradColor1: page.cfg_orbGradColor1
                    gradColor2: page.cfg_orbGradColor2
                    gradColor3: page.cfg_orbGradColor3
                    gradThree: page.cfg_orbGradThree
                    waveSpacing: page.cfg_orbWaveSpacing
                    stretch: page.previewStretch ? 1 : 0
                    logoAlign: page.cfg_orbLogoAlign
                    buttonStyle: page.cfg_buttonStyle
                    buttonText: page.cfg_buttonText
                    buttonColor: page.cfg_buttonColor
                    classicColor: page.cfg_classicButtonColor
                    hovered: previewMouse.containsMouse
                    pressed: previewMouse.pressed
                }
                MouseArea { id: previewMouse; anchors.fill: parent; hoverEnabled: true }
            }
            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("Hover and click the preview to see the hover and pressed looks.")
            }

        }
    }

    Kirigami.FormLayout {

        QQC2.RadioButton {
            Kirigami.FormData.label: i18n("Start button:")
            QQC2.ButtonGroup.group: modeGroup
            text: i18n("Orb (Vista / 7 style)")
            checked: page.cfg_orbMode !== "button"
            onToggled: if (checked) page.cfg_orbMode = "orb"
        }
        QQC2.RadioButton {
            QQC2.ButtonGroup.group: modeGroup
            text: i18n("Button (Win 9x / XP style)")
            checked: page.cfg_orbMode === "button"
            onToggled: if (checked) page.cfg_orbMode = "button"
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("This will give you the option of having an Orb (Vista/7 style), or a Button (Win 9x-XP)")
        }


        Item { Kirigami.FormData.isSection: true }

        ValueCombo {
            Kirigami.FormData.label: i18n("Orb style:")
            visible: page.cfg_orbMode !== "button"
            options: [
                { text: i18n("Glossy (Aero)"), value: "glossy" },
                { text: i18n("Plain (ring with logo)"), value: "plain" },
                { text: i18n("Flat (solid color)"), value: "flat" },
                { text: i18n("Custom image"), value: "custom" }
            ]
            current: page.cfg_orbStyle
            onPicked: v => page.cfg_orbStyle = v
        }

        ValueCombo {
            Kirigami.FormData.label: i18n("Orb shape:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle !== "custom"
            options: [
                { text: i18n("Orb (circle)"), value: "circle" },
                { text: i18n("Square"), value: "square" },
                { text: i18n("Rounded square"), value: "rounded" },
                { text: i18n("Hexagon"), value: "hexagon" },
                { text: i18n("Diamond"), value: "diamond" },
                { text: i18n("Octagon"), value: "octagon" },
                { text: i18n("Arrow (pointing right)"), value: "arrow" }
            ]
            current: page.cfg_orbShapeType
            onPicked: v => page.cfg_orbShapeType = v
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Stretch:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle !== "custom"
            text: i18n("Make the orb longer, like a Win 9x / XP button")
            checked: page.cfg_orbLengthOn
            onToggled: page.cfg_orbLengthOn = checked
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Orb length:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle !== "custom" && page.cfg_orbLengthOn
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: 60; to: 400; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_orbLength
                onMoved: page.cfg_orbLength = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_orbLength + " px"
            }
        }
        QQC2.Label {
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle !== "custom" && page.cfg_orbLengthOn
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Works like the button length: the ends keep their shape, only the middle grows, and the logo can sit left, center or right. The Orb Size setting then only changes the height. Works on horizontal panels.")
        }
        ValueCombo {
            Kirigami.FormData.label: i18n("Logo position:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle !== "custom" && page.cfg_orbLengthOn
            options: [
                { text: i18n("Left"), value: "left" },
                { text: i18n("Center"), value: "center" },
                { text: i18n("Right"), value: "right" }
            ]
            current: page.cfg_orbLogoAlign
            onPicked: v => page.cfg_orbLogoAlign = v
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Orb image:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle === "custom"
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_orbImage.replace("file://", "")
                placeholderText: i18n("No image chosen")
            }
            QQC2.Button {
                text: i18n("Browse…")
                icon.name: "document-open"
                onClicked: { imagePicker.target = "orbImage"; imagePicker.open() }
            }
        }

        QQC2.CheckBox {
            
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle === "custom"
            text: i18n("Image contains 3 states stacked vertically (normal / hover / pressed)")
            checked: page.cfg_orbThreeState
            onToggled: page.cfg_orbThreeState = checked
        }

        Item { Kirigami.FormData.isSection: true; visible: page.cfg_orbMode !== "button" }

        SizeRow {
            Kirigami.FormData.label: i18n("Orb Size:")
            visible: page.cfg_orbMode !== "button"
            value: page.cfg_orbSize
            lockedMax: 120
            unlocked: page.cfg_sizeUnlocked
            onEdited: v => page.cfg_orbSize = v
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Horizontal offset:")
            visible: page.cfg_orbMode !== "button"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: -24; to: 24; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_orbOffsetX
                onMoved: page.cfg_orbOffsetX = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_orbOffsetX + " px"
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Vertical offset:")
            visible: page.cfg_orbMode !== "button"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: -24; to: 24; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_orbOffsetY
                onMoved: page.cfg_orbOffsetY = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_orbOffsetY + " px"
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Rotation:")
            visible: page.cfg_orbMode !== "button"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: 0; to: 360; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_orbRotation
                onMoved: page.cfg_orbRotation = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_orbRotation + "°"
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Opacity:")
            visible: page.cfg_orbMode !== "button"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: 20; to: 100; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_orbOpacity
                onMoved: page.cfg_orbOpacity = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_orbOpacity + "%"
            }
        }

        QQC2.CheckBox {
            
            visible: page.cfg_orbMode !== "button"
            text: i18n("Flip horizontally")
            checked: page.cfg_orbFlip
            onToggled: page.cfg_orbFlip = checked
        }

        Item { Kirigami.FormData.isSection: true; visible: page.cfg_orbMode !== "button" }

        RowLayout {
            Kirigami.FormData.label: i18n("Color presets:")
            visible: page.cfg_orbMode !== "button"
            Repeater {
                model: ["#2f86d0", "#3a9a3a", "#e8832a", "#d33b3b", "#8a4fc7", "#e05fa3", "#5a5f66"]
                delegate: Rectangle {
                    implicitWidth: Kirigami.Units.gridUnit * 1.5
                    implicitHeight: implicitWidth
                    radius: width / 2
                    color: modelData
                    border.width: 1
                    border.color: Kirigami.Theme.disabledTextColor
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            page.cfg_orbColor = modelData
                            page.cfg_buttonColor = modelData
                        }
                    }
                }
            }
        }

        QQC2.Label {
            visible: page.cfg_orbRainbow && (page.cfg_orbMode !== "button" || page.cfg_buttonStyle === "xp")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Color effects are on (see below), so the orb and XP button use that color instead of the colors here. Turn them off to use your own color.")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Orb color:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle !== "custom"
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 3
                implicitHeight: Kirigami.Units.gridUnit * 1.4
                radius: 4
                color: page.cfg_orbColor
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        colorPicker.key = "orbColor"
                        colorPicker.selectedColor = page.cfg_orbColor !== "" ? page.cfg_orbColor : "#ffffff"
                        colorPicker.open()
                    }
                }
            }
            QQC2.Button {
                text: i18n("Choose…")
                onClicked: {
                    colorPicker.key = "orbColor"
                    colorPicker.selectedColor = page.cfg_orbColor !== "" ? page.cfg_orbColor : "#ffffff"
                    colorPicker.open()
                }
            }
        }

        QQC2.CheckBox {
            
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle === "glossy"
            text: i18n("Glass highlight")
            checked: page.cfg_orbGlass
            onToggled: page.cfg_orbGlass = checked
        }

        ValueCombo {
            Kirigami.FormData.label: i18n("Logo:")
            options: [
                { text: i18n("KDE logo"), value: "icon" },
                { text: i18n("Custom image"), value: "image" },
                { text: i18n("None"), value: "none" }
            ]
            current: page.cfg_orbLogoMode
            onPicked: v => page.cfg_orbLogoMode = v
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Logo image:")
            visible: page.cfg_orbLogoMode === "image"
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_orbLogoImage.replace("file://", "")
                placeholderText: i18n("No image chosen")
            }
            QQC2.Button {
                text: i18n("Browse…")
                icon.name: "document-open"
                onClicked: { imagePicker.target = "orbLogoImage"; imagePicker.open() }
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Logo color:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbLogoMode === "icon" && page.cfg_orbStyle !== "custom"
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 3
                implicitHeight: Kirigami.Units.gridUnit * 1.4
                radius: 4
                color: (page.cfg_orbLogoColor !== "" ? page.cfg_orbLogoColor : Kirigami.Theme.textColor)
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        colorPicker.key = "orbLogoColor"
                        colorPicker.selectedColor = page.cfg_orbLogoColor !== "" ? page.cfg_orbLogoColor : "#ffffff"
                        colorPicker.open()
                    }
                }
            }
            QQC2.Button {
                text: i18n("Choose…")
                onClicked: {
                    colorPicker.key = "orbLogoColor"
                    colorPicker.selectedColor = page.cfg_orbLogoColor !== "" ? page.cfg_orbLogoColor : "#ffffff"
                    colorPicker.open()
                }
            }
            QQC2.Button {
                text: i18n("Auto")
                onClicked: page.cfg_orbLogoColor = ""
            }
        }

        Item { Kirigami.FormData.isSection: true; visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle === "custom" }

        RowLayout {
            Kirigami.FormData.label: i18n("Tint color:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle === "custom"
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 3
                implicitHeight: Kirigami.Units.gridUnit * 1.4
                radius: 4
                color: page.cfg_orbTintColor
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        colorPicker.key = "orbTintColor"
                        colorPicker.selectedColor = page.cfg_orbTintColor !== "" ? page.cfg_orbTintColor : "#ffffff"
                        colorPicker.open()
                    }
                }
            }
            QQC2.Button {
                text: i18n("Choose…")
                onClicked: {
                    colorPicker.key = "orbTintColor"
                    colorPicker.selectedColor = page.cfg_orbTintColor !== "" ? page.cfg_orbTintColor : "#ffffff"
                    colorPicker.open()
                }
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Tint strength:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle === "custom"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: 0; to: 100; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_orbTintStrength
                onMoved: page.cfg_orbTintStrength = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_orbTintStrength + "%"
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Brightness:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle === "custom"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: -100; to: 100; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_orbBrightness
                onMoved: page.cfg_orbBrightness = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_orbBrightness + ""
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Contrast:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle === "custom"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: -100; to: 100; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_orbContrast
                onMoved: page.cfg_orbContrast = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_orbContrast + ""
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Saturation:")
            visible: page.cfg_orbMode !== "button" && page.cfg_orbStyle === "custom"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: -100; to: 100; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_orbSaturation
                onMoved: page.cfg_orbSaturation = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_orbSaturation + ""
            }
        }

        Item { Kirigami.FormData.isSection: true; visible: page.cfg_orbMode === "button" }

        ValueCombo {
            Kirigami.FormData.label: i18n("Button style:")
            visible: page.cfg_orbMode === "button"
            options: [
                { text: i18n("Classic (Windows 95/98)"), value: "classic" },
                { text: i18n("XP (Colored)"), value: "xp" }
            ]
            current: page.cfg_buttonStyle
            onPicked: v => page.cfg_buttonStyle = v
        }

        ValueCombo {
            Kirigami.FormData.label: i18n("Logo and text alignment:")
            visible: page.cfg_orbMode === "button"
            options: [
                { text: i18n("Left"), value: "left" },
                { text: i18n("Center"), value: "center" },
                { text: i18n("Right"), value: "right" }
            ]
            current: page.cfg_buttonAlign
            onPicked: v => page.cfg_buttonAlign = v
        }
        QQC2.TextField {
            Kirigami.FormData.label: i18n("Button text:")
            visible: page.cfg_orbMode === "button"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
            text: page.cfg_buttonText
            onTextEdited: page.cfg_buttonText = text
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Button length:")
            visible: page.cfg_orbMode === "button"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: 60; to: 400; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_buttonLength
                onMoved: page.cfg_buttonLength = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_buttonLength + " px"
            }
        }

        SizeRow {
            Kirigami.FormData.label: i18n("Classic Button Size:")
            visible: page.cfg_orbMode === "button" && page.cfg_buttonStyle === "classic"
            value: page.cfg_buttonSize
            lockedMax: 150
            unlocked: page.cfg_sizeUnlocked
            onEdited: v => page.cfg_buttonSize = v
        }
        SizeRow {
            Kirigami.FormData.label: i18n("XP Button Size:")
            visible: page.cfg_orbMode === "button" && page.cfg_buttonStyle === "xp"
            value: page.cfg_xpButtonSize
            lockedMax: 150
            unlocked: page.cfg_sizeUnlocked
            onEdited: v => page.cfg_xpButtonSize = v
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Horizontal offset:")
            visible: page.cfg_orbMode === "button"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: -24; to: 24; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_buttonOffsetX
                onMoved: page.cfg_buttonOffsetX = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_buttonOffsetX + " px"
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Vertical offset:")
            visible: page.cfg_orbMode === "button"
            QQC2.Slider {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                from: -24; to: 24; stepSize: 1
                snapMode: QQC2.Slider.SnapAlways
                value: page.cfg_buttonOffsetY
                onMoved: page.cfg_buttonOffsetY = Math.round(value)
            }
            QQC2.Label {
                Layout.minimumWidth: Kirigami.Units.gridUnit * 3
                text: page.cfg_buttonOffsetY + " px"
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Button color:")
            visible: page.cfg_orbMode === "button" && page.cfg_buttonStyle !== "xp"
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 3
                implicitHeight: Kirigami.Units.gridUnit * 1.4
                radius: 4
                color: page.cfg_classicButtonColor !== "" ? page.cfg_classicButtonColor : "#c0c0c0"
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        colorPicker.key = "classicButtonColor"
                        colorPicker.selectedColor = page.cfg_classicButtonColor !== "" ? page.cfg_classicButtonColor : "#c0c0c0"
                        colorPicker.open()
                    }
                }
            }
            QQC2.Button {
                text: i18n("Choose…")
                onClicked: {
                    colorPicker.key = "classicButtonColor"
                    colorPicker.selectedColor = page.cfg_classicButtonColor !== "" ? page.cfg_classicButtonColor : "#c0c0c0"
                    colorPicker.open()
                }
            }
            QQC2.Button {
                text: i18n("Reset to grey")
                icon.name: "edit-undo"
                enabled: page.cfg_classicButtonColor !== ""
                onClicked: page.cfg_classicButtonColor = ""
            }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Button color:")
            visible: page.cfg_orbMode === "button" && page.cfg_buttonStyle === "xp"
            Rectangle {
                implicitWidth: Kirigami.Units.gridUnit * 3
                implicitHeight: Kirigami.Units.gridUnit * 1.4
                radius: 4
                color: page.cfg_buttonColor
                border.width: 1
                border.color: Kirigami.Theme.disabledTextColor
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        colorPicker.key = "buttonColor"
                        colorPicker.selectedColor = page.cfg_buttonColor !== "" ? page.cfg_buttonColor : "#ffffff"
                        colorPicker.open()
                    }
                }
            }
            QQC2.Button {
                text: i18n("Choose…")
                onClicked: {
                    colorPicker.key = "buttonColor"
                    colorPicker.selectedColor = page.cfg_buttonColor !== "" ? page.cfg_buttonColor : "#ffffff"
                    colorPicker.open()
                }
            }
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Color effects:")
            text: i18n("Color the orb or button with an accent, animated or gradient color")
            checked: page.cfg_orbRainbow
            onToggled: page.cfg_orbRainbow = checked
        }
        ValueCombo {
            Kirigami.FormData.label: i18n("Color mode:")
            visible: page.cfg_orbRainbow
            options: [
                { text: i18n("Accent (system color)"), value: "accent" },
                { text: i18n("RGB color cycle"), value: "rgbcycle" },
                { text: i18n("Rainbow wave (scrolls sideways)"), value: "wave" },
                { text: i18n("Custom gradient"), value: "gradient" }
            ]
            current: page.cfg_orbColorMode
            onPicked: v => page.cfg_orbColorMode = v
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Wave spacing:")
            visible: page.cfg_orbRainbow && page.cfg_orbColorMode === "wave"
            QQC2.Label { text: i18n("Close"); opacity: 0.7 }
            QQC2.Slider {
                id: waveSlider
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                from: 20; to: 400; stepSize: 5
                value: page.cfg_orbWaveSpacing
                onMoved: page.cfg_orbWaveSpacing = Math.round(value)
            }
            QQC2.Label { text: i18n("Wide"); opacity: 0.7 }
            QQC2.Label { text: page.cfg_orbWaveSpacing + "%"; Layout.minimumWidth: Kirigami.Units.gridUnit * 2.5 }
        }
        RowLayout {
            Kirigami.FormData.label: i18n("Gradient colors:")
            visible: page.cfg_orbRainbow && page.cfg_orbColorMode === "gradient"
            Repeater {
                model: page.cfg_orbGradThree ? 3 : 2
                delegate: Rectangle {
                    required property int index
                    implicitWidth: Kirigami.Units.gridUnit * 3
                    implicitHeight: Kirigami.Units.gridUnit * 1.4
                    radius: 4
                    color: page["cfg_orbGradColor" + (index + 1)]
                    border.width: 1
                    border.color: Kirigami.Theme.disabledTextColor
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            colorPicker.key = "orbGradColor" + (parent.index + 1)
                            colorPicker.selectedColor = parent.color
                            colorPicker.open()
                        }
                    }
                }
            }
        }
        QQC2.CheckBox {
            visible: page.cfg_orbRainbow && page.cfg_orbColorMode === "gradient"
            text: i18n("Use a third color")
            checked: page.cfg_orbGradThree
            onToggled: page.cfg_orbGradThree = checked
        }
        SpeedRow {
            Kirigami.FormData.label: i18n("Effect speed:")
            visible: page.cfg_orbRainbow && page.cfg_orbColorMode !== "accent"
            seconds: page.cfg_orbRainbowSpeed
            onSpeedPicked: s => page.cfg_orbRainbowSpeed = s
        }

        QQC2.Label {
            visible: page.cfg_orbMode === "button"
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("The button shows the logo chosen above next to the text. Choose “None” for text only.")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.Button {
            Kirigami.FormData.label: i18n("Size limit:")
            icon.name: page.cfg_sizeUnlocked ? "object-locked" : "object-unlocked"
            text: page.cfg_sizeUnlocked ? i18n("Lock the limits (orb 120%, buttons 150%)") : i18n("Unlock")
            onClicked: {
                if (page.cfg_sizeUnlocked) {
                    page.cfg_orbSize = Math.min(120, page.cfg_orbSize)
                    page.cfg_buttonSize = Math.min(150, page.cfg_buttonSize)
                    page.cfg_xpButtonSize = Math.min(150, page.cfg_xpButtonSize)
                }
                page.cfg_sizeUnlocked = !page.cfg_sizeUnlocked
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            visible: true
            type: Kirigami.MessageType.Warning
            text: i18n("Unlocking the maximum size will result in weirdness, not recommended unless you have an idea")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Behaviour:")
            visible: page.cfg_orbMode !== "button"
            text: i18n("Glow on hover")
            checked: page.cfg_orbHoverGlow
            onToggled: page.cfg_orbHoverGlow = checked
        }

        QQC2.CheckBox {
            
            visible: page.cfg_orbMode !== "button"
            text: i18n("Shrink slightly when pressed")
            checked: page.cfg_orbPressAnim
            onToggled: page.cfg_orbPressAnim = checked
        }

        QQC2.Button {
            Kirigami.FormData.label: i18n("Reset:")
            text: i18n("Reset orb / button to defaults")
            icon.name: "edit-undo"
            onClicked: {
                page.cfg_orbMode = page.cfg_orbModeDefault
                page.cfg_orbShapeType = page.cfg_orbShapeTypeDefault
                page.cfg_orbLengthOn = page.cfg_orbLengthOnDefault
                page.cfg_orbLength = page.cfg_orbLengthDefault
                page.cfg_orbLogoAlign = page.cfg_orbLogoAlignDefault
                page.cfg_orbRainbow = page.cfg_orbRainbowDefault
                page.cfg_orbRainbowSpeed = page.cfg_orbRainbowSpeedDefault
                page.cfg_orbColorMode = page.cfg_orbColorModeDefault
                page.cfg_orbWaveSpacing = page.cfg_orbWaveSpacingDefault
                page.cfg_orbGradColor1 = page.cfg_orbGradColor1Default
                page.cfg_orbGradColor2 = page.cfg_orbGradColor2Default
                page.cfg_orbGradColor3 = page.cfg_orbGradColor3Default
                page.cfg_orbGradThree = page.cfg_orbGradThreeDefault
                page.cfg_buttonSize = page.cfg_buttonSizeDefault
                page.cfg_xpButtonSize = page.cfg_xpButtonSizeDefault
                page.cfg_buttonAlign = page.cfg_buttonAlignDefault
                page.cfg_buttonOffsetX = page.cfg_buttonOffsetXDefault
                page.cfg_buttonOffsetY = page.cfg_buttonOffsetYDefault
                page.cfg_sizeUnlocked = page.cfg_sizeUnlockedDefault
                page.cfg_orbStyle = page.cfg_orbStyleDefault
                page.cfg_orbImage = page.cfg_orbImageDefault
                page.cfg_orbThreeState = page.cfg_orbThreeStateDefault
                page.cfg_orbSize = page.cfg_orbSizeDefault
                page.cfg_orbOffsetX = page.cfg_orbOffsetXDefault
                page.cfg_orbOffsetY = page.cfg_orbOffsetYDefault
                page.cfg_orbRotation = page.cfg_orbRotationDefault
                page.cfg_orbOpacity = page.cfg_orbOpacityDefault
                page.cfg_orbFlip = page.cfg_orbFlipDefault
                page.cfg_orbColor = page.cfg_orbColorDefault
                page.cfg_orbGlass = page.cfg_orbGlassDefault
                page.cfg_orbLogoMode = page.cfg_orbLogoModeDefault
                page.cfg_orbLogoImage = page.cfg_orbLogoImageDefault
                page.cfg_orbLogoColor = page.cfg_orbLogoColorDefault
                page.cfg_orbTintColor = page.cfg_orbTintColorDefault
                page.cfg_orbTintStrength = page.cfg_orbTintStrengthDefault
                page.cfg_orbBrightness = page.cfg_orbBrightnessDefault
                page.cfg_orbContrast = page.cfg_orbContrastDefault
                page.cfg_orbSaturation = page.cfg_orbSaturationDefault
                page.cfg_orbHoverGlow = page.cfg_orbHoverGlowDefault
                page.cfg_orbPressAnim = page.cfg_orbPressAnimDefault
                page.cfg_buttonStyle = page.cfg_buttonStyleDefault
                page.cfg_buttonText = page.cfg_buttonTextDefault
                page.cfg_buttonLength = page.cfg_buttonLengthDefault
                page.cfg_buttonColor = page.cfg_buttonColorDefault
                page.cfg_classicButtonColor = page.cfg_classicButtonColorDefault
            }
        }
    }
}
