import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import QtQuick.Layouts

// ViPER FX: ViPER4Android's effects, laid out like its app (a master switch,
// headphone and speaker modes, one card per effect), in DD Party's look.
ApplicationWindow {
    id: win
    width: 1120; height: 780
    minimumWidth: 420; minimumHeight: 480
    visible: true
    title: "ViPER FX"
    color: Theme.bg

    function v(key) { viper.revision; return viper.get(key) }
    readonly property bool headphone: viper.profile === "headphone"
    readonly property bool wide: width >= 880

    function db(v100) { var d = 20 * Math.log(Math.max(v100, 1) / 100) / Math.LN10; return (d >= 0 ? "+" : "") + d.toFixed(1) + " dB" }

    // ViPER4Android's Dynamic System devices: x low/high, y low/high (Hz), side gain x/y (%).
    readonly property var devices: [
        ["Extreme headphone (v2)", 140, 6200, 40, 60, 10, 80],
        ["High-end headphone (v2)", 180, 5800, 55, 80, 10, 70],
        ["Common headphone (v2)", 300, 5600, 60, 105, 10, 50],
        ["Low-end headphone (v2)", 600, 5400, 60, 105, 10, 20],
        ["Common earphone (v2)", 100, 5600, 40, 80, 50, 50],
        ["Extreme headphone (v1)", 1200, 6200, 40, 80, 0, 20],
        ["High-end headphone (v1)", 1000, 6200, 40, 80, 0, 10],
        ["Common headphone (v1)", 800, 6200, 40, 80, 10, 0],
        ["Common earphone (v1)", 400, 6200, 40, 80, 10, 0],
        ["Apple earphone", 1200, 6200, 50, 90, 15, 10],
        ["Monster earphone", 1000, 6200, 50, 90, 30, 10],
        ["Moto earphone", 1100, 6200, 60, 100, 20, 0],
        ["Philips earphone", 1200, 6200, 50, 100, 10, 50],
        ["SHP2000", 1200, 6200, 60, 100, 0, 30],
        ["SHP9000", 1200, 6200, 40, 80, 0, 30],
        ["Unknown type I", 1000, 6200, 60, 100, 0, 0],
        ["Unknown type II", 1000, 6200, 60, 120, 0, 0],
        ["Unknown type III", 1000, 6200, 80, 140, 0, 0],
        ["Unknown type IV", 800, 6200, 80, 140, 0, 0]
    ]
    readonly property var eqBands: ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    readonly property var eqPresets: [
        ["Flat", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]],
        ["Bass", [600, 500, 400, 200, 0, 0, 0, 0, 0, 0]],
        ["Rock", [450, 350, 200, -50, -150, 0, 200, 350, 450, 450]],
        ["Pop", [-100, 0, 200, 350, 400, 300, 100, 0, -50, -100]],
        ["Jazz", [300, 200, 100, 200, -150, -150, 0, 150, 300, 350]],
        ["Classical", [400, 300, 200, 100, -100, -100, 0, 200, 300, 400]],
        ["Vocal", [-200, -150, -100, 100, 350, 400, 300, 150, 0, -100]],
        ["Electronic", [450, 400, 150, 0, -150, 200, 100, 150, 450, 500]],
        ["Treble", [0, 0, 0, 0, 0, 100, 250, 400, 550, 600]]
    ]

    FileDialog {
        id: ddcDialog
        title: "Choose a ViPER-DDC file (.vdc)"
        options: FileDialog.DontUseNativeDialog
        nameFilters: ["ViPER-DDC (*.vdc)", "All files (*)"]
        onAccepted: viper.loadDdc(selectedFile)
    }
    FileDialog {
        id: irDialog
        title: "Choose an impulse response (.wav, .irs)"
        options: FileDialog.DontUseNativeDialog
        nameFilters: ["Impulse responses (*.wav *.irs)", "All files (*)"]
        onAccepted: viper.loadConvolver(selectedFile)
    }

    Popup {
        id: savePopup
        anchors.centerIn: parent
        width: 340; modal: true; padding: 18
        implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
        background: Chamfer { fill: Theme.card; stroke: Theme.magentaText }
        contentItem: ColumnLayout {
            spacing: 12
            Text { text: "SAVE PRESET"; color: Theme.text; font.family: Theme.heading; font.pixelSize: 14 }
            TextField {
                id: presetName
                Layout.fillWidth: true
                placeholderText: "Preset name"
                color: Theme.text; font.family: Theme.body
                background: Rectangle { color: Theme.view; border.color: presetName.activeFocus ? Theme.magentaText : Theme.border }
                onAccepted: saveBtn.clicked()
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                DDButton { text: "Cancel"; onClicked: savePopup.close() }
                DDButton { id: saveBtn; text: "Save"; accent: true; onClicked: { if (viper.savePreset(presetName.text)) savePopup.close() } }
            }
        }
    }

    // ---- Header: name, power, status, meters, modes, presets ----
    header: Rectangle {
        color: Theme.header
        implicitHeight: hcol.implicitHeight + 24
        Rainbow { anchors.bottom: parent.bottom; width: parent.width; opacity: viper.power ? 1 : 0.25 }
        ColumnLayout {
            id: hcol
            x: 16; y: 12; width: parent.width - 32
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                spacing: 14
                Image { source: "qrc:/icons/viperfx.svg"; sourceSize: Qt.size(40, 40); Layout.preferredWidth: 40; Layout.preferredHeight: 40 }
                ColumnLayout {
                    spacing: 2
                    Layout.fillWidth: true
                    Text { text: "VIPER FX"; color: Theme.text; font.family: Theme.heading; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: 2 }
                    Text {
                        text: viper.connected ? viper.status : "Not connected: " + viper.status
                        color: viper.connected ? (viper.flowing && viper.power ? Theme.magentaText : Theme.muted) : Theme.rainbow[0]
                        font.family: Theme.body; font.pixelSize: 13
                        Layout.fillWidth: true; elide: Text.ElideRight
                    }
                }
                Row {
                    spacing: 3
                    Layout.preferredHeight: 44
                    Meter { height: 44; level: viper.inL }
                    Meter { height: 44; level: viper.inR }
                    Item { width: 6; height: 1 }
                    Meter { height: 44; level: viper.outL }
                    Meter { height: 44; level: viper.outR }
                }
                ColumnLayout {
                    spacing: 2
                    Text { text: viper.power ? "ON" : "OFF"; color: viper.power ? Theme.magentaText : Theme.dim; font.family: Theme.heading; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                    DDSwitch { checked: viper.power; onToggled: on => viper.power = on; implicitWidth: 58; implicitHeight: 28 }
                }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 10
                DDChoice {
                    width: 260
                    options: ["Headphone", "Speaker"]
                    current: win.headphone ? 0 : 1
                    onPicked: i => viper.profile = i === 0 ? "headphone" : "speaker"
                }
                Row {
                    spacing: 6
                    ComboBox {
                        id: presetBox
                        width: 180; height: 30
                        model: viper.presets
                        displayText: count === 0 ? "No presets yet" : currentText
                        font.family: Theme.body
                        background: Chamfer { fill: Theme.button; stroke: Theme.border; cut: 7 }
                        contentItem: Text { leftPadding: 10; text: presetBox.displayText; color: Theme.text; font: presetBox.font; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                    }
                    DDButton { text: "Load"; enabled: presetBox.count > 0; onClicked: viper.loadPreset(presetBox.currentText) }
                    DDButton { text: "Save"; onClicked: { presetName.text = ""; savePopup.open(); presetName.forceActiveFocus() } }
                    DDButton { text: "Delete"; enabled: presetBox.count > 0; onClicked: viper.deletePreset(presetBox.currentText) }
                    DDButton { text: "Reset"; onClicked: viper.resetProfile() }
                }
            }
        }
    }

    // ---- The effects ----
    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: grid.implicitHeight + 32
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            contentItem: Rectangle { implicitWidth: 6; color: Theme.magenta; opacity: 0.8 }
        }
        opacity: viper.power ? 1 : 0.55
        Behavior on opacity { NumberAnimation { duration: 150 } }

        GridLayout {
            id: grid
            x: 16; y: 16; width: flick.width - 32
            columns: win.wide ? 2 : 1
            columnSpacing: 14
            rowSpacing: 14

            ColumnLayout {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 1
                spacing: 14

                Card {
                    title: "Master limiter"
                    subtitle: "Output volume, balance and the final limiter"
                    DDSlider { label: "Output volume"; from: 10; to: 200; value: v("master.volume"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("master.volume", x) }
                    DDSlider { label: "Channel pan"; from: -100; to: 100; value: v("master.pan"); format: x => x === 0 ? "Center" : (x < 0 ? "L " + (-x) : "R " + x); onMoved: x => viper.set("master.pan", x) }
                    DDSlider { label: "Limiter threshold"; from: 30; to: 100; value: v("master.limit"); format: x => win.db(x); onMoved: x => viper.set("master.limit", x) }
                }
                Card {
                    title: "Playback gain control"; key: "agc.enable"
                    subtitle: "Evens out loud and quiet tracks"
                    DDChoice { label: "Strength"; options: ["Light", "Moderate", "Strong"];
                        current: [50, 100, 300].indexOf(v("agc.ratio")) < 0 ? 1 : [50, 100, 300].indexOf(v("agc.ratio"))
                        onPicked: i => viper.set("agc.ratio", [50, 100, 300][i]) }
                    DDChoice { label: "Maximum gain"; options: ["1×", "2×", "3×", "4×", "6×", "8×", "10×"]
                        current: Math.max(0, [100, 200, 300, 400, 600, 800, 1000].indexOf(v("agc.maxgain")))
                        onPicked: i => viper.set("agc.maxgain", [100, 200, 300, 400, 600, 800, 1000][i]) }
                    DDSlider { label: "Output threshold"; from: 10; to: 100; value: v("agc.volume"); format: x => win.db(x); onMoved: x => viper.set("agc.volume", x) }
                }
                Card {
                    title: "ViPER-DDC"; key: "ddc.enable"
                    subtitle: "Device-specific tuning from a .vdc file"
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: viper.ddcName !== "" ? viper.ddcName : "No file loaded"; color: viper.ddcName !== "" ? Theme.magentaText : Theme.dim; font.family: Theme.body; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideMiddle }
                        DDButton { text: "Choose…"; onClicked: ddcDialog.open() }
                        DDButton { text: "Clear"; visible: viper.ddcName !== ""; onClicked: viper.clearDdc() }
                    }
                }
                Card {
                    title: "Spectrum extension"; key: "spectrum.enable"
                    subtitle: "Rebuilds the high end lossy files cut off"
                    DDSlider { label: "Strength"; from: 0; to: 100; value: v("spectrum.strength"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("spectrum.strength", x) }
                }
                Card {
                    id: eqCard
                    title: "FIR equalizer"; key: "eq.enable"
                    DDChoice {
                        options: win.eqPresets.map(p => p[0])
                        current: v("eq.preset")
                        onPicked: i => {
                            var m = { "eq.preset": i }
                            for (var b = 0; b < 10; b++) m["eq.band" + b] = win.eqPresets[i][1][b]
                            viper.setMany(m)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 190
                        spacing: 2
                        Repeater {
                            model: 10
                            ColumnLayout {
                                id: band
                                required property int index
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 2
                                Text { text: (bs.value > 0 ? "+" : "") + (bs.value / 100).toFixed(1); color: Theme.magentaText; font.family: Theme.body; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                                Slider {
                                    id: bs
                                    orientation: Qt.Vertical
                                    Layout.fillHeight: true; Layout.alignment: Qt.AlignHCenter
                                    from: -1200; to: 1200; stepSize: 50; snapMode: Slider.SnapAlways
                                    Binding on value { value: v("eq.band" + band.index); when: !bs.pressed }
                                    onMoved: viper.set("eq.band" + band.index, value)
                                    background: Item {
                                        x: bs.leftPadding + bs.availableWidth / 2 - 3; y: bs.topPadding
                                        width: 6; height: bs.availableHeight
                                        Rectangle { anchors.fill: parent; color: Theme.empty; border.color: Theme.borderSoft }
                                        Rectangle { width: parent.width; height: 1; y: parent.height / 2; color: Theme.dim }
                                        Rectangle {
                                            width: parent.width
                                            readonly property real mid: parent.height / 2
                                            readonly property real pos: bs.visualPosition * parent.height
                                            y: Math.min(mid, pos); height: Math.abs(mid - pos)
                                            color: Theme.rainbow[band.index % 7]
                                            opacity: eqCard.on ? 1 : 0.35
                                        }
                                    }
                                    handle: Rectangle {
                                        x: bs.leftPadding + bs.availableWidth / 2 - width / 2
                                        y: bs.topPadding + bs.visualPosition * (bs.availableHeight - height)
                                        width: 20; height: 12; color: bs.pressed ? Theme.magentaHi : Theme.magenta; border.color: Theme.magentaText
                                    }
                                }
                                Text { text: win.eqBands[band.index]; color: Theme.dim; font.family: Theme.body; font.pixelSize: 11; Layout.alignment: Qt.AlignHCenter }
                            }
                        }
                    }
                }
                Card {
                    title: "Convolver"; key: "conv.enable"
                    subtitle: "Plays everything through an impulse response (a room, a speaker, a headphone)"
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: viper.convName !== "" ? viper.convName : "No impulse response loaded"; color: viper.convName !== "" ? Theme.magentaText : Theme.dim; font.family: Theme.body; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideMiddle }
                        DDButton { text: "Choose…"; onClicked: irDialog.open() }
                        DDButton { text: "Clear"; visible: viper.convName !== ""; onClicked: viper.clearConvolver() }
                    }
                }
                Text {
                    visible: viper.fileError !== ""
                    text: viper.fileError
                    color: Theme.rainbow[0]; font.family: Theme.body; font.pixelSize: 13
                    Layout.fillWidth: true; wrapMode: Text.WordWrap
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 1
                spacing: 14

                Card {
                    title: "Field surround"; key: "field.enable"
                    DDSlider { label: "Surround strength"; from: 0; to: 800; value: v("field.widen"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("field.widen", x) }
                    DDSlider { label: "Mid image"; from: 0; to: 200; value: v("field.mid"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("field.mid", x) }
                    DDSlider { label: "Depth"; from: 0; to: 1000; value: v("field.depth"); onMoved: x => viper.set("field.depth", x) }
                }
                Card {
                    title: "Differential surround"; key: "diff.enable"
                    DDSlider { label: "Delay"; from: 100; to: 2000; stepSize: 10; value: v("diff.delay"); format: x => (x / 100).toFixed(1) + " ms"; onMoved: x => viper.set("diff.delay", x) }
                }
                Card {
                    visible: win.headphone
                    title: "Headphone surround +"; key: "vhe.enable"
                    subtitle: "Virtual speakers in your headphones"
                    DDChoice { label: "Level"; options: ["1", "2", "3", "4", "5"]; current: v("vhe.level"); onPicked: i => viper.set("vhe.level", i) }
                }
                Card {
                    title: "Reverberation"; key: "reverb.enable"
                    DDSlider { label: "Room size"; value: v("reverb.room"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("reverb.room", x) }
                    DDSlider { label: "Sound field"; value: v("reverb.width"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("reverb.width", x) }
                    DDSlider { label: "Damping"; value: v("reverb.damp"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("reverb.damp", x) }
                    DDSlider { label: "Wet signal"; value: v("reverb.wet"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("reverb.wet", x) }
                    DDSlider { label: "Dry signal"; value: v("reverb.dry"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("reverb.dry", x) }
                }
                Card {
                    title: "Dynamic system"; key: "dynsys.enable"
                    subtitle: "Bass and dynamics tuned to your device"
                    ComboBox {
                        id: devBox
                        Layout.fillWidth: true; implicitWidth: 200; implicitHeight: 30
                        model: win.devices.map(d => d[0])
                        currentIndex: v("dynsys.device")
                        font.family: Theme.body
                        background: Chamfer { fill: Theme.button; stroke: Theme.border; cut: 7 }
                        contentItem: Text { leftPadding: 10; text: devBox.displayText; color: Theme.text; font: devBox.font; verticalAlignment: Text.AlignVCenter }
                        onActivated: i => {
                            var d = win.devices[i]
                            viper.setMany({ "dynsys.device": i, "dynsys.xlow": d[1], "dynsys.xhigh": d[2], "dynsys.ylow": d[3],
                                            "dynsys.yhigh": d[4], "dynsys.sidex": d[5], "dynsys.sidey": d[6] })
                        }
                    }
                    DDSlider { label: "Strength"; value: v("dynsys.strength"); format: x => Math.round(x) + " %"; onMoved: x => viper.set("dynsys.strength", x) }
                }
                Card {
                    title: "Tube simulator (6N1J)"; key: "tube.enable"
                    subtitle: "Warm valve-amp colour"
                }
                Card {
                    title: "ViPER bass"; key: "bass.enable"
                    DDChoice { label: "Mode"; options: ["Natural bass", "Pure bass +", "Subwoofer"]; current: v("bass.mode"); onPicked: i => viper.set("bass.mode", i) }
                    DDSlider { label: "Speaker size"; from: 15; to: 300; value: v("bass.freq"); format: x => Math.round(x) + " Hz"; onMoved: x => viper.set("bass.freq", x) }
                    DDSlider { label: "Bass gain"; from: 0; to: 600; stepSize: 5; value: v("bass.gain"); format: x => "×" + (x / 100).toFixed(2); onMoved: x => viper.set("bass.gain", x) }
                }
                Card {
                    title: "ViPER clarity"; key: "clarity.enable"
                    DDChoice { label: "Mode"; options: ["Natural", "OZone +", "XHiFi"]; current: v("clarity.mode"); onPicked: i => viper.set("clarity.mode", i) }
                    DDSlider { label: "Clarity"; from: 0; to: 450; stepSize: 5; value: v("clarity.gain"); format: x => "×" + (x / 100).toFixed(2); onMoved: x => viper.set("clarity.gain", x) }
                }
                Card {
                    visible: win.headphone
                    title: "Auditory system protection"; key: "cure.enable"
                    subtitle: "Cure+ crossfeed: less fatigue on long listens"
                    DDChoice { label: "Level"; options: ["Slight", "Moderate", "Extreme"]; current: v("cure.level"); onPicked: i => viper.set("cure.level", i) }
                }
                Card {
                    title: "AnalogX"; key: "analogx.enable"
                    DDChoice { label: "Level"; options: ["Slight", "Moderate", "Extreme"]; current: v("analogx.level"); onPicked: i => viper.set("analogx.level", i) }
                }
                Card {
                    visible: !win.headphone
                    title: "Speaker optimization"; key: "speaker.enable"
                    subtitle: "Corrects a small phone or laptop speaker"
                }
                Card {
                    title: "About"
                    note: "ViPER FX " + viper.version + " for DeskDroid. The effects are ViPERFX_RE, the open reimplementation of ViPER4Android's engine (by Iscle and Martmists; ViPER4Android by ViPER520 and Zhuhang). FET Compressor isn't in that engine yet. Closing this window keeps the effects running while the switch below is on."
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "Keep processing after closing the window"; color: Theme.soft; font.family: Theme.body; font.pixelSize: 13; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                        DDSwitch { checked: viper.keepRunning; onToggled: on => viper.keepRunning = on }
                    }
                }
            }
        }
    }
}
