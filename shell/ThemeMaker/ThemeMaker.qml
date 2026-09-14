import QtQuick
import QtQuick.Dialogs
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Ui as CompatUi
import "../Settings"
import "Palette.js" as Palette

FocusScope {
    id: root
    signal closeRequested()
    property bool windowActive: true
    property bool allowClose: false
    property bool confirmClose: false
    property bool modalOpen: false
    property Item modalTrigger: null
    property bool ready: false
    property bool compareOriginal: false
    property bool editorVisible: !compact
    property string section: "Basics"
    property string selectedRole: "background"
    property var draft: ({name:"My theme",palette:{},background:{enabled:false,image:"",motion:"",dim:.25,panelOpacity:.94,paused:false},linked:true})
    property var originalDraft: null
    property var savedDraft: null
    property var themes: []
    property string baseTheme: ""
    property var undoStack: []
    property var redoStack: []
    property string committed: ""
    property string savedState: ""
    property string message: "Loading your current theme…"
    property bool failed: false
    property var hsl: [0,0,0]
    property string mediaError: ""
    // Chrome stays readable even while deliberately testing a low-contrast draft.
    property color chromeBackground: Theme.bg
    property color chromeForeground: Theme.fg
    property color chromeAccent: Theme.accent
    property color chromeMuted: Theme.fgDim
    readonly property color chromeBorder: Theme.mix(chromeBackground,chromeForeground,.3)
    readonly property bool dirty: ready && JSON.stringify(draft) !== savedState
    readonly property bool compact: width < Theme.cellW * 110
    readonly property bool busy: worker.running
    readonly property var visibleRoles: Palette.roles.filter(r => r.group === section)
    readonly property real textContrast: ready ? Theme.contrast(draft.palette.foreground,draft.palette.background) : 1
    readonly property real secondaryContrast: ready ? Theme.contrast(draft.palette.dark_foreground,draft.palette.background) : 1
    readonly property bool canAnimate: windowActive && !Theme.reducedMotion && !draft.background.paused
    readonly property string motionPath: draft.background.motion || ""
    readonly property bool gif: motionPath.toLowerCase().endsWith(".gif")
    focus: true

    function normalized(raw) {
        var next=Palette.clone(raw), p=Theme.normalize(Palette.clone(raw.palette));
        // Match Theme fallbacks when a base omits optional color roles.
        p.bright_foreground=p.bright_foreground || p.foreground;
        p.red=p.red || "#f7768e";p.green=p.green || "#9ece6a";
        p.yellow=p.yellow || "#e0af68";p.magenta=p.magenta || "#ad8ee6";
        p.cyan=p.cyan || "#449dab";p.orange=p.orange || p.yellow;
        next.palette={};
        for (const role of Palette.roles) next.palette[role.key]=String(Qt.color(p[role.key] || p.accent || "#7aa2f7")).slice(0,7);
        next.palette.inactive_border_color=p.inactive_border_color || p.muted || p.dark_foreground;
        if (!p.outer_border_color) delete next.palette.outer_border_color;
        for (const role of Palette.bright) next.palette["bright_"+role]=String(Qt.color(p["bright_"+role] || p[role] || p.accent || "#7aa2f7"));
        if (Number.isFinite(Number(p.border_width))) next.palette.border_width=Math.max(1,Math.min(8,Math.round(Number(p.border_width))));
        next.palette.mode=p.mode || "dark";
        return next;
    }
    function updatePreview() {
        if (!ready) return;
        Theme.c=Palette.clone(compareOriginal && originalDraft ? originalDraft.palette : draft.palette);
    }
    function syncHsl() { hsl=Palette.hsl(draft.palette[selectedRole] || "#000000"); }
    function replaceState(next, commitNow) {
        draft=next; updatePreview();
        if (commitNow) commit();
    }
    function commit() {
        var current=JSON.stringify(draft);
        if (current===committed) return;
        if (committed) undoStack=undoStack.concat([committed]).slice(-80);
        redoStack=[]; committed=current;
    }
    function undo() {
        commit();
        if (!undoStack.length) return;
        redoStack=redoStack.concat([committed]);
        committed=undoStack[undoStack.length-1]; undoStack=undoStack.slice(0,-1);
        draft=JSON.parse(committed); updatePreview(); syncHsl();
    }
    function redo() {
        if (!redoStack.length) return;
        undoStack=undoStack.concat([committed]);
        committed=redoStack[redoStack.length-1]; redoStack=redoStack.slice(0,-1);
        draft=JSON.parse(committed); updatePreview(); syncHsl();
    }
    function setColor(value, finish) {
        if (!/^#[0-9a-fA-F]{6}$/.test(value)) { message="Use a six-digit color such as #7aa2f7."; failed=true; return; }
        var next=Palette.clone(draft); next.palette[selectedRole]=value.toLowerCase();
        if (next.linked && ["background","foreground"].includes(selectedRole)) next.palette=Palette.linked(next.palette);
        replaceState(next,finish); failed=false; message="Preview only · your desktop is unchanged";
    }
    function setHsl(index,value) {
        var next=hsl.slice();next[index]=value;hsl=next;
        setColor(Palette.fromHsl(...hsl),false);
    }
    function setBackground(key,value,finish) {
        var next=Palette.clone(draft);next.background[key]=value;replaceState(next,finish);mediaError="";
    }
    function request(action,extra) {
        if (busy) return;
        commit(); failed=false; message=action==="apply" ? "Applying temporary preview…" : "Working…";
        worker.action=action;
        worker.requestState=JSON.stringify(draft);
        worker.payload=JSON.stringify(Object.assign({action:action,state:draft},extra||{}));
        worker.handled=false; worker.stdinEnabled=true; worker.running=true;
    }
    function chooseMedia(kind) {
        chooser.kind=kind;
        chooser.title=kind==="image" ? "Choose a background image" : "Choose a video or GIF loop";
        chooser.nameFilters=kind==="image" ? ["Images (*.png *.jpg *.jpeg *.webp *.bmp)"] : ["Animated backgrounds (*.gif *.mp4 *.webm *.mkv *.mov)"];
        chooser.open();
    }
    onSelectedRoleChanged: if (ready) syncHsl()
    onCompareOriginalChanged: updatePreview()
    Component.onCompleted: {
        chromeBackground=Theme.bg; chromeForeground=Theme.readable(Theme.fg,Theme.bg);
        chromeAccent=Theme.readable(Theme.accent,Theme.bg); chromeMuted=Theme.readable(Theme.fgDim,Theme.bg);
        Theme.sourceEnabled=false;
        Theme.accentRoleOverride="theme";
        request("init");
    }

    Process {
        id: worker
        property string action: ""
        property string payload: ""
        property string requestState: ""
        property bool handled: true
        command: ["python3",decodeURIComponent(Qt.resolvedUrl("../scripts/theme-maker.py").toString().replace("file://",""))]
        onStarted: { write(payload+"\n");payload="";stdinEnabled=false; }
        onRunningChanged: if (!running) Qt.callLater(() => {
            if (!worker.running && !worker.handled) { root.failed=true;root.message="Theme Maker helper could not start.";worker.handled=true; }
        })
        stdout: StdioCollector { id: output }
        onExited: code => {
            handled=true;
            var result;
            try { result=JSON.parse(output.text); } catch(e) { result={ok:false,error:"Could not read the Theme Maker result."}; }
            root.failed=code!==0 || !result.ok;
            if (root.failed) { root.message=result.error || "Theme operation failed.";return; }
            if (action==="init" || action==="load") {
                if (action==="init") { root.themes=result.themes;root.baseTheme=result.selected;root.savedDraft=result.draft; }
                var next=root.normalized(result.state);
                if (action==="init") {
                    root.chromeBackground=next.palette.background;
                    root.chromeForeground=Theme.readable(next.palette.foreground,next.palette.background);
                    root.chromeAccent=Theme.readable(next.palette.accent,next.palette.background);
                    root.chromeMuted=Theme.readable(next.palette.dark_foreground,next.palette.background);
                }
                root.originalDraft=Palette.clone(next);root.draft=next;root.ready=true;root.compareOriginal=false;
                root.replaceState(next,action==="load");root.committed=JSON.stringify(next);
                if (action==="init") root.savedState=root.committed;
                root.syncHsl();root.message="Preview only · your desktop is unchanged";
            } else {
                root.message=result.message;
                if (["draft","save","export"].includes(action)) root.savedState=requestState;
                if (action==="draft") root.savedDraft=JSON.parse(requestState);
                if (result.name && action!=="export") root.themes=root.themes.concat([result.name]);
            }
        }
    }

    FileDialog {
        id: chooser
        property string kind: "image"
        fileMode: FileDialog.OpenFile
        onAccepted: {
            var url=String(selectedFile);
            if (url.startsWith("file:///")) {
                root.setBackground(kind,decodeURIComponent(url.slice(7)),false);
                root.setBackground("enabled",true,true);
            }
        }
    }
    FolderDialog {
        id: folderChooser
        title: "Choose a background folder"
        onAccepted: { chooser.currentFolder=selectedFolder;root.message="Background folder selected. Choose an image or loop."; }
    }
    FolderDialog {
        id: exportChooser
        title: "Export theme to folder"
        onAccepted: root.request("export",{folder:decodeURIComponent(String(selectedFolder).slice(7))})
    }
    ColorDialog {
        id: colorChooser
        title: "Choose "+root.selectedRole.replace(/_/g," ")
        onAccepted: { root.setColor(String(selectedColor).slice(0,7),true);root.syncHsl(); }
    }
    Shortcut { enabled:root.ready&&!root.busy&&!root.confirmClose&&!root.modalOpen; sequence:"Ctrl+Z"; onActivated: root.undo() }
    Shortcut { enabled:root.ready&&!root.busy&&!root.confirmClose&&!root.modalOpen; sequence:"Ctrl+Shift+Z"; onActivated: root.redo() }
    Shortcut { enabled:root.ready&&!root.busy&&!root.confirmClose&&!root.modalOpen; sequence:"Ctrl+S"; onActivated: root.request("draft") }
    Shortcut { enabled:root.ready&&!root.busy&&!root.confirmClose&&!root.modalOpen; sequence:"Ctrl+Q"; onActivated: root.closeRequested() }
    Keys.onEscapePressed: {
        if (compareOriginal) compareOriginal=false;
        else if (compact && editorVisible) editorVisible=false;
        else root.closeRequested();
    }

    component EditorButton: ControlButton {
        textColor: root.chromeForeground
        selectedTextColor: root.chromeBackground
        color: selected ? root.chromeAccent : root.chromeBackground
        border.color: visualFocus ? root.chromeAccent : root.chromeBorder
        implicitHeight: Theme.controlHeight
    }
    component EditorField: TextField {
        foreground: root.chromeForeground
        placeholderTextColor: root.chromeMuted
        selectionColor: root.chromeAccent
        selectedTextColor: root.chromeBackground
        background: Rectangle { color: root.chromeBackground;radius:Theme.radius;border.width:Theme.borderWidth;border.color:parent.activeFocus?root.chromeAccent:root.chromeBorder }
    }
    component EditorLabel: Line { color: root.chromeForeground }
    component SliderRow: Column {
        id: sliderRow
        property string label: ""
        property real value: 0
        property real maximum: 100
        signal moved(real value)
        signal finished()
        width: parent.width
        EditorLabel { width:parent.width;text:sliderRow.label+"  "+Math.round(sliderRow.value);font.pixelSize:Theme.fontCaption }
        CompatUi.PanelSlider {
            width:parent.width
            accessibleName:sliderRow.label
            activeFocusOnTab:true
            value:sliderRow.value; minimum:0;maximum:sliderRow.maximum;step:1
            trackColor:root.chromeBorder;fillColor:root.chromeAccent;knobColor:root.chromeForeground
            onMoved:value=>sliderRow.moved(value)
            onReleased:sliderRow.finished()
        }
    }

    Column {
        id: layout
        anchors.fill:parent
        spacing:0
        Rectangle {
            width:parent.width
            height:header.implicitHeight+Theme.spaceMd*2
            color:root.chromeBackground
            Flow {
                id:header
                x:Theme.spaceMd;y:Theme.spaceMd
                width:parent.width-Theme.spaceMd*2
                spacing:Theme.spaceSm
                EditorLabel { text:"THEME MAKER";height:Theme.controlHeight;verticalAlignment:Text.AlignVCenter;font.bold:true;font.pixelSize:Theme.fontTitle }
                EditorButton { text:root.editorVisible?"Hide editor":"Edit theme";onTriggered:root.editorVisible=!root.editorVisible }
                EditorButton { text:"Undo";enabled:root.undoStack.length>0&&!root.busy;onTriggered:root.undo() }
                EditorButton { text:"Redo";enabled:root.redoStack.length>0&&!root.busy;onTriggered:root.redo() }
                EditorButton { text:root.compareOriginal?"Original":"Compare";selected:root.compareOriginal;enabled:root.ready;onTriggered:root.compareOriginal=!root.compareOriginal }
                EditorButton { text:"Save draft";enabled:root.ready&&!root.busy;onTriggered:root.request("draft") }
                EditorButton { text:"Save theme";enabled:root.ready&&!root.busy;onTriggered:root.request("save") }
                EditorButton { text:"Reset preview";enabled:root.ready&&!root.busy;onTriggered:root.request("reset-preview") }
                EditorButton { text:"Apply";selected:true;enabled:root.ready&&!root.busy;onTriggered:root.request("apply") }
            }
        }
        Item {
            id:body
            width:parent.width
            height:Math.max(0,layout.height-y-footer.height)
            Item {
                id:preview
                x:0;y:0
                width:root.editorVisible&&!root.compact ? parent.width-sidebar.width : parent.width
                height:parent.height
                clip:true
                Rectangle { anchors.fill:parent;color:Theme.bg }
                Image {
                    anchors.fill:parent
                    source:root.draft.background.enabled?Palette.localUrl(root.draft.background.image):""
                    fillMode:Image.PreserveAspectCrop
                    asynchronous:true
                    onStatusChanged:if(status===Image.Error)root.mediaError="The background image could not be loaded."
                }
                Loader {
                    id:videoLoader
                    anchors.fill:parent
                    active:root.draft.background.enabled && root.motionPath!=="" && !root.gif && root.canAnimate
                    source:"BackgroundVideo.qml"
                    onLoaded:item.source=Palette.localUrl(root.motionPath)
                    Connections { target:root;function onMotionPathChanged(){if(videoLoader.item)videoLoader.item.source=Palette.localUrl(root.motionPath);} }
                    Connections { target:videoLoader.item;function onFailed(message){root.mediaError=message;} }
                }
                Loader {
                    anchors.fill:parent
                    active:root.draft.background.enabled && root.gif && root.motionPath!==""
                    sourceComponent:Component {
                        AnimatedImage {
                            cache: false
                            source:Palette.localUrl(root.motionPath)
                            fillMode:Image.PreserveAspectCrop
                            playing:root.canAnimate
                            onStatusChanged:if(status===Image.Error)root.mediaError="The GIF could not be loaded."
                        }
                    }
                }
                Rectangle { anchors.fill:parent;color:"black";opacity:root.draft.background.enabled?root.draft.background.dim:0 }
                Flickable {
                    id:galleryScroll
                    anchors.fill:parent
                    anchors.margins:Theme.spaceLg
                    contentWidth:width
                    contentHeight:gallery.height+Theme.panelPadding*2
                    clip:true
                    boundsBehavior:Flickable.StopAtBounds
                    PanelSurface {
                        width:galleryScroll.width
                        height:gallery.height+Theme.panelPadding*2
                        color:Theme.alpha(Theme.bg,root.draft.background.enabled?root.draft.background.panelOpacity:1)
                        GalleryContent {
                            id:gallery
                            x:Theme.panelPadding;y:Theme.panelPadding
                            width:Math.max(1,parent.width-Theme.panelPadding*2)
                            onModalRequested:trigger=>{root.modalTrigger=trigger;root.modalOpen=true;}
                        }
                    }
                    Controls.ScrollBar.vertical: Controls.ScrollBar {}
                }
                EditorLabel {
                    anchors.right:parent.right;anchors.top:parent.top;anchors.margins:Theme.spaceMd
                    visible:root.compareOriginal
                    text:"ORIGINAL";color:Theme.readable(Theme.accent,Theme.bg);font.bold:true
                }
            }
            Rectangle {
                id:sidebar
                visible:root.editorVisible
                enabled:root.ready&&!root.busy
                width:Math.min(parent.width,Theme.cellW*37)
                height:parent.height
                anchors.right:parent.right
                color:root.chromeBackground
                border.width:Theme.borderWidth;border.color:root.chromeBorder
                Flickable {
                    id:editorScroll
                    anchors.fill:parent;anchors.margins:Theme.spaceMd
                    contentWidth:width;contentHeight:editor.implicitHeight
                    clip:true;boundsBehavior:Flickable.StopAtBounds
                    Column {
                        id:editor
                        width:editorScroll.width
                        spacing:Theme.spaceMd
                        EditorLabel { text:"EDIT THEME";font.bold:true }
                        EditorField {
                            width:parent.width
                            text:root.draft.name
                            accessibleName:"Theme name"
                            placeholderText:"Theme name"
                            onTextEdited:{var next=Palette.clone(root.draft);next.name=text;root.replaceState(next,false);}
                            onEditingFinished:root.commit()
                        }
                        Flow {
                            width:parent.width;spacing:Theme.spaceXs
                            Repeater {
                                model:["Basics","Accents","Surfaces","Background","Files"]
                                EditorButton {
                                    required property string modelData
                                    text:modelData;selected:root.section===modelData
                                    onTriggered:{root.section=modelData;if(root.visibleRoles.length)root.selectedRole=root.visibleRoles[0].key;}
                                }
                            }
                        }
                        Column {
                            width:parent.width;spacing:Theme.spaceSm
                            visible:["Basics","Accents","Surfaces"].includes(root.section)
                            Flow {
                                width:parent.width;spacing:Theme.spaceXs
                                Repeater {
                                    model:root.visibleRoles
                                    EditorButton {
                                        required property var modelData
                                        text:modelData.label
                                        selected:root.selectedRole===modelData.key
                                        onTriggered:root.selectedRole=modelData.key
                                    }
                                }
                            }
                            Rectangle {
                                width:parent.width;height:Theme.controlHeight*1.5
                                color:root.draft.palette[root.selectedRole] || root.chromeBackground
                                border.width:Theme.borderWidth;border.color:root.chromeBorder
                            }
                            Row {
                                width:parent.width;spacing:Theme.spaceSm
                                EditorField {
                                    width:parent.width-picker.width-parent.spacing
                                    text:root.draft.palette[root.selectedRole] || ""
                                    accessibleName:"Hex color"
                                    maximumLength:7
                                    onTextEdited:if(/^#[0-9a-fA-F]{6}$/.test(text)){root.setColor(text,false);root.syncHsl();}
                                    onEditingFinished:{root.setColor(text,true);root.syncHsl();}
                                }
                                EditorButton { id:picker;text:"Pick";onTriggered:{colorChooser.selectedColor=root.draft.palette[root.selectedRole];colorChooser.open();} }
                            }
                            SliderRow { label:"Hue";value:root.hsl[0];maximum:360;onMoved:value=>root.setHsl(0,value);onFinished:root.commit() }
                            SliderRow { label:"Saturation";value:root.hsl[1];onMoved:value=>root.setHsl(1,value);onFinished:root.commit() }
                            SliderRow { label:"Lightness";value:root.hsl[2];onMoved:value=>root.setHsl(2,value);onFinished:root.commit() }
                            EditorButton {
                                text:root.draft.linked?"Linked surfaces: on":"Linked surfaces: off"
                                selected:root.draft.linked
                                onTriggered:{var next=Palette.clone(root.draft);next.linked=!next.linked;root.replaceState(next,true);}
                            }
                            EditorLabel { width:parent.width;text:"Linked surfaces follow background and text edits. Turn off to tune them separately.";wrapMode:Text.WordWrap;font.pixelSize:Theme.fontCaption;color:root.chromeMuted }
                            Row {
                                spacing:Theme.spaceSm
                                Repeater {
                                    model:["dark","light"]
                                    EditorButton {
                                        required property string modelData
                                        text:modelData;selected:root.draft.palette.mode===modelData
                                        onTriggered:{var next=Palette.clone(root.draft);next.palette.mode=modelData;root.replaceState(next,true);}
                                    }
                                }
                            }
                            EditorLabel { width:parent.width;text:"Text contrast  "+root.textContrast.toFixed(1)+":1";font.bold:true }
                            EditorLabel { width:parent.width;text:root.textContrast>=4.5?"Body text: good contrast":"Body text: below 4.5:1";wrapMode:Text.WordWrap }
                            EditorLabel { width:parent.width;text:"Secondary text  "+root.secondaryContrast.toFixed(1)+":1";color:root.chromeMuted }
                        }
                        Column {
                            width:parent.width;spacing:Theme.spaceMd
                            visible:root.section==="Background"
                            EditorButton { text:root.draft.background.enabled?"Background: on":"Background: off";selected:root.draft.background.enabled;onTriggered:root.setBackground("enabled",!root.draft.background.enabled,true) }
                            EditorButton { text:"Choose folder…";onTriggered:folderChooser.open() }
                            Flow {
                                width:parent.width;spacing:Theme.spaceSm
                                EditorButton { text:"Choose image…";onTriggered:root.chooseMedia("image") }
                                EditorButton { text:"Clear image";enabled:root.draft.background.image!=="";onTriggered:root.setBackground("image","",true) }
                            }
                            EditorLabel { width:parent.width;text:root.draft.background.image.split("/").pop()||"No still image";elide:Text.ElideMiddle;color:root.chromeMuted }
                            EditorButton { text:"Choose video / GIF…";onTriggered:root.chooseMedia("motion") }
                            EditorLabel { width:parent.width;text:root.motionPath.split("/").pop()||"No animation";elide:Text.ElideMiddle;color:root.chromeMuted }
                            Flow {
                                width:parent.width;spacing:Theme.spaceSm
                                EditorButton { text:root.draft.background.paused?"Play":"Pause";onTriggered:root.setBackground("paused",!root.draft.background.paused,true) }
                                EditorButton { text:"Clear loop";onTriggered:root.setBackground("motion","",true) }
                            }
                            SliderRow { label:"Preview dimming";value:root.draft.background.dim*100;onMoved:value=>root.setBackground("dim",value/100,false);onFinished:root.commit() }
                            SliderRow { label:"Preview panel opacity";value:root.draft.background.panelOpacity*100;onMoved:value=>root.setBackground("panelOpacity",value/100,false);onFinished:root.commit() }
                            EditorLabel { width:parent.width;text:"Dimming and opacity are preview aids. Enabled media is included when saving. Apply previews it on the desktop without saving a theme.";wrapMode:Text.WordWrap;font.pixelSize:Theme.fontCaption;color:root.chromeMuted }
                            EditorLabel { width:parent.width;visible:Theme.reducedMotion;text:"Reduced Motion: animation paused";wrapMode:Text.WordWrap }
                            EditorLabel { width:parent.width;text:root.mediaError;visible:text!=="";wrapMode:Text.WordWrap }
                        }
                        Column {
                            width:parent.width;spacing:Theme.spaceSm
                            visible:root.section==="Files"
                            EditorLabel { text:"Start from an installed theme" }
                            Controls.ComboBox {
                                id:basePicker
                                width:parent.width
                                model:root.themes
                                currentIndex:Math.max(0,root.themes.indexOf(root.baseTheme))
                                palette.button:root.chromeBackground;palette.buttonText:root.chromeForeground
                                palette.base:root.chromeBackground;palette.text:root.chromeForeground
                                font.family:Theme.fontFamily;font.pixelSize:Theme.fontBody
                                onActivated:root.baseTheme=currentText
                            }
                            EditorButton { text:"Load base theme";enabled:!root.busy;onTriggered:root.request("load",{name:root.baseTheme}) }
                            EditorButton { text:"Restore saved draft";enabled:root.savedDraft!==null;onTriggered:{root.replaceState(root.normalized(root.savedDraft),true);root.syncHsl();} }
                            EditorButton { text:"Export theme folder…";enabled:root.ready&&!root.busy;onTriggered:exportChooser.open() }
                            EditorLabel { width:parent.width;text:"Save theme creates a new entry in your theme library. Existing themes are never overwritten. Export creates a portable folder with colors.toml and enabled media.";wrapMode:Text.WordWrap;font.pixelSize:Theme.fontCaption;color:root.chromeMuted }
                            EditorLabel { width:parent.width;text:"Ctrl+S  Save draft\nCtrl+Z  Undo\nCtrl+Shift+Z  Redo";color:root.chromeMuted }
                        }
                    }
                    Controls.ScrollBar.vertical:Controls.ScrollBar {}
                }
            }
        }
        Rectangle {
            id:footer
            width:parent.width
            height:status.implicitHeight+Theme.spaceMd*2
            color:root.chromeBackground
            EditorLabel {
                id:status
                x:Theme.spaceMd;y:Theme.spaceMd;width:parent.width-Theme.spaceMd*2
                text:(root.failed?"Error: ":"")+root.message+(root.dirty?" · Unsaved changes":"")
                wrapMode:Text.WordWrap;font.pixelSize:Theme.fontCaption
            }
        }
    }
    ModalSurface {
        visible:root.confirmClose
        panel.color:root.chromeBackground
        anchors.fill:parent
        blockedItem:layout
        dialogTitle:"Unsaved theme"
        preferredWidth:Theme.cellW*46
        preferredHeight:closeContent.implicitHeight+Theme.panelPadding*2
        onCloseRequested:root.confirmClose=false
        Column {
            id:closeContent
            anchors.centerIn:parent
            width:parent.width-Theme.panelPadding*2
            spacing:Theme.spaceMd
            EditorLabel { width:parent.width;text:"Save a draft before closing, or discard your changes.";wrapMode:Text.WordWrap }
            Row {
                spacing:Theme.spaceSm
                EditorButton { text:"Keep editing";onTriggered:root.confirmClose=false }
                EditorButton { text:"Discard";onTriggered:{root.allowClose=true;root.closeRequested();} }
            }
        }
    }
    ModalSurface {
        visible:root.modalOpen
        anchors.fill:parent
        blockedItem:layout
        restoreFocusItem:root.modalTrigger
        dialogTitle:"Modal preview"
        preferredWidth:Theme.cellW*42
        preferredHeight:Theme.cellH*9
        onCloseRequested:root.modalOpen=false
        ActionButton { anchors.centerIn:parent;text:"Close preview";onTriggered:root.modalOpen=false }
    }
}
