import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// The panel button: orb or Win 9x/XP style button, driven by the widget settings
Item {
    id: orbRoot

    property bool active: false
    signal toggled()

    readonly property var cfg: Plasmoid.configuration
    readonly property bool isButton: cfg.orbMode === "button"
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // stretch only makes sense for the built-in shapes on a horizontal panel
    readonly property bool stretchOn: !isButton && !vertical && cfg.orbStyle !== "custom" && cfg.orbLengthOn
    readonly property real stretch: stretchOn ? 1 : 0
    readonly property real orbLength: stretchOn ? cfg.orbLength : Kirigami.Units.iconSizes.medium

    Layout.minimumWidth: isButton && !vertical ? cfg.buttonLength : orbLength
    Layout.preferredWidth: isButton && !vertical ? cfg.buttonLength : orbLength
    Layout.maximumWidth: isButton && !vertical ? cfg.buttonLength : (stretch > 0 ? orbLength : Number.POSITIVE_INFINITY)
    Layout.minimumHeight: isButton && vertical ? Kirigami.Units.iconSizes.medium + 8 : Kirigami.Units.iconSizes.medium
    Layout.preferredHeight: isButton && vertical ? Kirigami.Units.iconSizes.medium + 8 : Kirigami.Units.iconSizes.medium

    OrbVisual {
        anchors.fill: parent

        mode: orbRoot.cfg.orbMode
        style: orbRoot.cfg.orbStyle
        shapeKind: orbRoot.cfg.orbShapeType
        imageSource: orbRoot.cfg.orbImage
        threeState: orbRoot.cfg.orbThreeState
        sizeFraction: orbRoot.cfg.orbSize / 100
        offsetX: orbRoot.cfg.orbOffsetX
        offsetY: orbRoot.cfg.orbOffsetY
        orbRotation: orbRoot.cfg.orbRotation
        orbOpacity: orbRoot.cfg.orbOpacity / 100
        flipped: orbRoot.cfg.orbFlip
        baseColor: orbRoot.cfg.orbColor
        glass: orbRoot.cfg.orbGlass
        logoMode: orbRoot.cfg.orbLogoMode
        logoImage: orbRoot.cfg.orbLogoImage
        logoColor: orbRoot.cfg.orbLogoColor
        tintColor: orbRoot.cfg.orbTintColor
        tintStrength: orbRoot.cfg.orbTintStrength / 100
        brightness: orbRoot.cfg.orbBrightness / 100
        contrast: orbRoot.cfg.orbContrast / 100
        saturation: orbRoot.cfg.orbSaturation / 100
        hoverGlow: orbRoot.cfg.orbHoverGlow
        pressAnimation: orbRoot.cfg.orbPressAnim
        rainbow: orbRoot.cfg.orbRainbow
        rainbowSpeed: orbRoot.cfg.orbRainbowSpeed
        colorMode: orbRoot.cfg.orbColorMode
        gradColor1: orbRoot.cfg.orbGradColor1
        gradColor2: orbRoot.cfg.orbGradColor2
        gradColor3: orbRoot.cfg.orbGradColor3
        gradThree: orbRoot.cfg.orbGradThree
        waveSpacing: orbRoot.cfg.orbWaveSpacing
        stretch: orbRoot.stretch
        logoAlign: orbRoot.cfg.orbLogoAlign
        buttonStyle: orbRoot.cfg.buttonStyle
        buttonText: orbRoot.cfg.buttonText
        buttonColor: orbRoot.cfg.buttonColor
        classicColor: orbRoot.cfg.classicButtonColor
        buttonSizeFraction: (orbRoot.cfg.buttonStyle === "xp" ? orbRoot.cfg.xpButtonSize : orbRoot.cfg.buttonSize) / 100
        buttonAlign: orbRoot.cfg.buttonAlign
        buttonOffsetX: orbRoot.cfg.buttonOffsetX
        buttonOffsetY: orbRoot.cfg.buttonOffsetY

        hovered: ma.containsMouse
        pressed: ma.pressed
        active: orbRoot.active
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: orbRoot.toggled()
    }
}
