import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

// Pure visual for the panel button: an orb (Vista/7 style) or a classic button (Win 9x/XP style).
// Used by the panel (Orb.qml) and by the live preview in the settings.
Item {
    id: v

    property string mode: "orb"             // "orb" | "button"
    property string style: "glossy"         // glossy | plain | flat | custom
    property string shapeKind: "circle"     // circle | square | hexagon (built-in styles)
    property string imageSource: ""
    property bool threeState: false         // custom image = 3 stacked states (normal / hover / pressed)
    property real sizeFraction: 0.9
    property real offsetX: 0
    property real offsetY: 0
    property real orbRotation: 0
    property real orbOpacity: 1
    property bool flipped: false
    property string baseColor: "#2f86d0"
    property bool glass: true
    property string logoMode: "icon"        // icon | image | none
    property string logoImage: ""
    property string logoColor: ""           // "" = automatic
    property string tintColor: "#ffffff"
    property real tintStrength: 0           // 0..1
    property real brightness: 0             // -1..1
    property real contrast: 0
    property real saturation: 0
    property bool hoverGlow: true
    property bool pressAnimation: true
    property bool rainbow: true
    property int rainbowSpeed: 8            // seconds per colour cycle
    property string colorMode: "accent"     // accent | rgbcycle | wave | gradient (used when rainbow is on)
    property color gradColor1: "#ff3d81"
    property color gradColor2: "#3d8bff"
    property color gradColor3: "#3dffb0"
    property bool gradThree: false
    property int waveSpacing: 100           // % of the shape's length that one full rainbow covers
    property string logoAlign: "center"     // left | center | right (stretched orbs only)
    property real stretch: 0                // extra length as a fraction (1 = twice as long)
    property string buttonStyle: "classic"  // classic | xp
    property string buttonText: "Start"
    property string buttonColor: "#3a9a3a"
    property string classicColor: ""        // "" = the classic grey
    property real buttonSizeFraction: 1.0
    property string buttonAlign: "left"     // left | center | right
    property real buttonOffsetX: 0
    property real buttonOffsetY: 0

    property bool hovered: false
    property bool pressed: false
    property bool active: false

    // ---- derived values ----
    property real hue: 0
    NumberAnimation on hue {
        running: v.rainbow && v.colorMode !== "accent" && v.visible
        from: 0; to: 1; duration: Math.max(1, v.rainbowSpeed) * 1000
        loops: Animation.Infinite
    }
    function mixC(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    // the single colour every effect mode boils down to (it is animated through `hue`)
    // the scrolling rainbow can be painted over the built-in orb shapes and the XP button
    readonly property bool waveOverlay: rainbow && colorMode === "wave"
        && ((mode === "orb" && effStyle !== "custom") || (mode === "button" && buttonStyle === "xp"))
    readonly property color fxColor: {
        switch (colorMode) {
        case "rgbcycle": return Qt.hsla(hue, 0.9, 0.5, 1)
        case "wave":
            // with the overlay the shape keeps a calm base so the shading shows through; otherwise
            // (custom image, classic button) the colour just sweeps up and down the spectrum
            return waveOverlay ? Qt.hsla(0.62, 0.35, 0.45, 1)
                               : Qt.hsla(0.5 - 0.5 * Math.cos(hue * 2 * Math.PI), 0.9, 0.5, 1)
        case "gradient": {
            var stops = gradThree ? [gradColor1, gradColor2, gradColor3] : [gradColor1, gradColor2]
            var n = stops.length
            var x = hue * n
            var i = Math.min(n - 1, Math.floor(x))
            // smooth ease between neighbours, looping back to the first colour
            var f = x - i
            f = f * f * (3 - 2 * f)
            return mixC(stops[i], stops[(i + 1) % n], f)
        }
        default:         return Kirigami.Theme.highlightColor
        }
    }
    readonly property color baseC: rainbow ? fxColor : baseColor
    readonly property color tintC: rainbow ? fxColor : tintColor
    readonly property color buttonC: rainbow ? Qt.darker(fxColor, 1.2) : buttonColor
    readonly property string effStyle: (style === "custom" && imageSource === "") ? "glossy" : style
    readonly property color logoC: logoColor !== "" ? logoColor : (effStyle === "plain" ? baseC : "white")
    readonly property bool down: pressed || active
    readonly property color classicFace: classicColor !== "" ? classicColor : "#c0c0c0"
    readonly property bool classicDark: (0.299 * classicFace.r + 0.587 * classicFace.g + 0.114 * classicFace.b) < 0.5

    // =====================================================================  ORB
    Item {
        id: orbShape
        visible: v.mode === "orb"
        readonly property real d: Math.min(v.width, v.height) * v.sizeFraction
        // Stretched, the orb behaves like the Win 9x / XP buttons: it fills its whole slot
        // (the length), only the height follows the size setting, and the offset moves it sideways.
        readonly property bool stretched: v.stretch > 0
        width: stretched ? v.width : d
        height: d
        x: stretched ? v.offsetX : (v.width - d) / 2 + v.offsetX
        function logoX(w) {
            var pad = height * 0.22
            if (!stretched || v.logoAlign === "center") return (width - w) / 2
            return v.logoAlign === "left" ? pad : width - w - pad
        }
        y: (v.height - d) / 2 + v.offsetY
        rotation: v.orbRotation
        opacity: v.orbOpacity
        scale: (v.pressed && v.pressAnimation) ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 80 } }
        transform: Scale {
            origin.x: orbShape.width / 2
            origin.y: orbShape.height / 2
            xScale: v.flipped ? -1 : 1
        }

        // hover / open glow (built-in glossy and flat shapes)
        ShapeFill {
            visible: v.effStyle === "glossy" || v.effStyle === "flat"
            anchors.centerIn: parent
            width: parent.width + 6
            height: parent.height + 6
            kind: v.shapeKind
            fillColor: Qt.lighter(v.baseC, 1.6)
            opacity: v.active ? 0.55 : ((v.hovered && v.hoverGlow) ? 0.4 : 0)
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        // 1) Glossy (Aero)
        ShapeFill {
            visible: v.effStyle === "glossy"
            anchors.fill: parent
            kind: v.shapeKind
            useGradient: true
            topColor: Qt.lighter(v.baseC, 1.55)
            midColor: v.baseC
            bottomColor: Qt.darker(v.baseC, 2.3)
            borderColor: Qt.lighter(v.baseC, 1.9)
            borderWidth: 1

            Rectangle { // glass highlight, fitted to the shape
                visible: v.glass
                readonly property bool hex: v.shapeKind === "hexagon" || v.shapeKind === "diamond" || v.shapeKind === "octagon" || v.shapeKind === "arrow"
                readonly property bool sq: v.shapeKind === "square" || v.shapeKind === "rounded"
                width: parent.width * (hex ? 0.48 : (sq ? 0.86 : 0.78))
                height: parent.height * (hex ? 0.26 : (sq ? 0.4 : 0.46))
                x: (parent.width - width) / 2
                y: parent.height * (hex ? 0.14 : (sq ? 0.05 : 0.05))
                radius: sq ? 3 : height / 2
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.65) }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.05) }
                }
            }
        }

        // 2) Plain: just an outline in the orb color, otherwise transparent
        ShapeFill {
            visible: v.effStyle === "plain"
            anchors.fill: parent
            kind: v.shapeKind
            fillColor: (v.hovered || v.active) ? Qt.rgba(v.baseC.r, v.baseC.g, v.baseC.b, 0.15) : "transparent"
            borderColor: v.baseC
            borderWidth: Math.max(2, height * 0.06)
        }

        // 3) Flat: solid color, no gradient
        ShapeFill {
            visible: v.effStyle === "flat"
            anchors.fill: parent
            kind: v.shapeKind
            fillColor: v.baseC
        }

        // pressed / hover tint on the glossy and flat shapes
        ShapeFill {
            visible: v.effStyle === "glossy" || v.effStyle === "flat"
            anchors.fill: parent
            kind: v.shapeKind
            fillColor: "white"
            opacity: v.pressed ? 0.25 : (v.hovered ? 0.12 : 0)
        }

        // scrolling rainbow (wave mode), clipped to the visible shape
        ShapeFill {
            id: orbWaveMask
            visible: false
            anchors.fill: parent
            layer.enabled: true
            kind: v.shapeKind
            fillColor: v.effStyle === "plain" ? "transparent" : "black"
            borderColor: "black"
            borderWidth: v.effStyle === "plain" ? Math.max(2, height * 0.06) : 0
        }
        WaveOverlay {
            visible: v.waveOverlay && v.mode === "orb"
            anchors.fill: parent
            maskItem: orbWaveMask
            period: parent.width * v.waveSpacing / 100
            phase: v.hue
            opacity: v.effStyle === "plain" ? 1 : 0.8
        }

        // logo inside the built-in orbs
        Kirigami.Icon {
            visible: v.effStyle !== "custom" && v.logoMode === "icon"
            width: parent.height * 0.56
            height: width
            x: orbShape.logoX(width)
            y: (parent.height - height) / 2
            source: "start-here-kde-symbolic"
            isMask: true
            color: v.logoC
        }
        Image {
            visible: v.effStyle !== "custom" && v.logoMode === "image" && v.logoImage !== ""
            width: parent.height * 0.6
            height: width
            x: orbShape.logoX(width)
            y: (parent.height - height) / 2
            source: v.logoImage
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        // 4) Custom image (optionally 3 stacked states), with colour adjustments
        Image {
            id: probe
            visible: false
            source: v.effStyle === "custom" ? v.imageSource : ""
        }
        Image {
            id: customImg
            visible: false
            anchors.fill: parent
            source: probe.source
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            sourceClipRect: (v.threeState && probe.status === Image.Ready)
                ? Qt.rect(0,
                          Math.floor(probe.implicitHeight / 3) * (v.pressed ? 2 : ((v.hovered || v.active) ? 1 : 0)),
                          probe.implicitWidth,
                          Math.floor(probe.implicitHeight / 3))
                : Qt.rect(0, 0, 0, 0)
        }
        MultiEffect {
            visible: v.effStyle === "custom" && customImg.status === Image.Ready
            anchors.fill: customImg
            source: customImg
            colorization: v.rainbow ? 0.6 : v.tintStrength
            colorizationColor: v.tintC
            brightness: v.brightness + (v.threeState ? 0 : (v.pressed ? -0.06 : (v.hovered ? 0.08 : 0)))
            contrast: v.contrast
            saturation: v.saturation
        }
    }

    // =====================================================================  BUTTON (Win 9x / XP)
    Item {
        id: btn
        visible: v.mode === "button"
        width: parent.width
        height: parent.height * v.buttonSizeFraction
        x: v.buttonOffsetX
        y: (parent.height - height) / 2 + v.buttonOffsetY

        readonly property bool xp: v.buttonStyle === "xp"
        readonly property real iconSide: Math.round(height * 0.7)
        readonly property real gap: Math.max(3, Math.round(height * 0.12))
        readonly property real pad: Math.max(4, Math.round(height * 0.2))
        readonly property bool hasIcon: (v.logoMode === "icon") || (v.logoMode === "image" && v.logoImage !== "")

        // --- classic Windows 95/98 bevel ---
        Item {
            visible: !btn.xp
            anchors.fill: parent
            Rectangle { anchors.fill: parent;  color: v.down ? "#ffffff" : "#000000" }
            Rectangle { width: parent.width - 1; height: parent.height - 1; color: v.down ? "#000000" : "#ffffff" }
            Rectangle { x: 1; y: 1; width: parent.width - 2; height: parent.height - 2; color: v.down ? "#dfdfdf" : "#808080" }
            Rectangle { x: 1; y: 1; width: parent.width - 3; height: parent.height - 3; color: v.down ? "#808080" : "#dfdfdf" }
            Rectangle { x: 2; y: 2; width: parent.width - 4; height: parent.height - 4; color: v.classicFace }
        }

        // --- Windows XP "Luna" style ---
        Rectangle {
            id: xpFace
            visible: btn.xp
            anchors.fill: parent
            readonly property color c: v.down ? Qt.darker(v.buttonC, 1.2) : (v.hovered ? Qt.lighter(v.buttonC, 1.12) : v.buttonC)
            topLeftRadius: 4
            bottomLeftRadius: 4
            topRightRadius: height * 0.45
            bottomRightRadius: height * 0.45
            border.width: 1
            border.color: Qt.darker(c, 1.8)
            gradient: Gradient {
                GradientStop { position: 0.0;  color: Qt.lighter(xpFace.c, 1.4) }
                GradientStop { position: 0.45; color: xpFace.c }
                GradientStop { position: 1.0;  color: Qt.darker(xpFace.c, 1.4) }
            }
        }

        Rectangle {
            id: xpWaveMask
            visible: false
            anchors.fill: parent
            layer.enabled: true
            color: "black"
            topLeftRadius: 4
            bottomLeftRadius: 4
            topRightRadius: height * 0.45
            bottomRightRadius: height * 0.45
        }
        WaveOverlay {
            visible: v.waveOverlay && v.mode === "button"
            anchors.fill: parent
            maskItem: xpWaveMask
            period: parent.width * v.waveSpacing / 100
            phase: v.hue
            opacity: 0.75
        }

        // --- icon + label ---
        Row {
            id: content
            readonly property real nudge: (!btn.xp && v.down) ? 1 : 0
            x: (v.buttonAlign === "left" ? btn.pad
                : (v.buttonAlign === "right" ? btn.width - width - btn.pad
                   : (btn.width - width) / 2)) + nudge
            y: (btn.height - height) / 2 + nudge
            spacing: btn.gap

            Kirigami.Icon {
                visible: v.logoMode === "icon"
                width: btn.iconSide
                height: btn.iconSide
                anchors.verticalCenter: parent.verticalCenter
                source: "start-here-kde"
            }
            Image {
                visible: v.logoMode === "image" && v.logoImage !== ""
                width: btn.iconSide
                height: btn.iconSide
                anchors.verticalCenter: parent.verticalCenter
                source: v.logoImage
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: v.buttonText
                color: btn.xp ? "white" : (v.classicDark ? "white" : "black")
                font.bold: true
                font.italic: btn.xp
                font.pixelSize: Math.max(10, Math.round(btn.height * 0.42))
                style: btn.xp ? Text.Raised : Text.Normal
                styleColor: Qt.darker(v.buttonC, 2.2)
                elide: Text.ElideRight
                width: Math.min(implicitWidth, Math.max(0, btn.width - btn.pad * 2 - (btn.hasIcon ? btn.iconSide + btn.gap : 0)))
            }
        }
    }
}
