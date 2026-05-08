import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var games: []
    property bool isLoading: false
    property string statusMessage: ""

    Component.onCompleted: {
        console.log("DMS-Lutris: Plugin initialized")
        fetchGames()
    }

    ListModel {
        id: gamesModel
    }

    function fetchGames() {
        console.log("DMS-Lutris: Fetching games...")
        isLoading = true
        statusMessage = "Loading games..."
        
        Proc.runCommand(
            "lutris-fetch",
            ["/usr/bin/lutris", "-l", "-o", "-j"],
            function(output, exitCode) {
                console.log("DMS-Lutris: Fetch finished with exit code: " + exitCode)
                isLoading = false
                if (exitCode !== 0 && exitCode !== 124) { // 124 is timeout but might have data
                    statusMessage = "Error fetching games"
                    return
                }
                if (!output || output.trim() === "") {
                    console.log("DMS-Lutris: No output from Lutris")
                    gamesModel.clear()
                    statusMessage = "No installed games found"
                    return
                }
                try {
                    // Clean output: remove lines starting with date, WARNING, or ERROR
                    var lines = output.split("\n")
                    var cleanLines = lines.filter(function(line) {
                        var trimmed = line.trim()
                        if (trimmed.length === 0) return false
                        // Matches "2024-05-08 18:34:44,385: ..."
                        if (/^\d{4}-\d{2}-\d{2}/.test(trimmed)) return false
                        if (/^WARNING:/.test(trimmed)) return false
                        if (/^ERROR:/.test(trimmed)) return false
                        if (/^INFO/.test(trimmed)) return false
                        return true
                    })
                    
                    var cleanJson = cleanLines.join("\n")
                    // Still try to find the array if there's garbage at start/end
                    var start = cleanJson.indexOf("[")
                    var end = cleanJson.lastIndexOf("]")
                    if (start === -1 || end === -1) {
                        console.error("DMS-Lutris: No JSON array found after cleaning")
                        statusMessage = "Data format error"
                        return
                    }
                    cleanJson = cleanJson.substring(start, end + 1)
                    
                    var parsedGames = JSON.parse(cleanJson)
                    console.log("DMS-Lutris: Parsed " + parsedGames.length + " games")
                    
                    parsedGames.sort((a, b) => (a.name || "").localeCompare(b.name || ""))
                    
                    gamesModel.clear()
                    for (var i = 0; i < parsedGames.length; i++) {
                        gamesModel.append(parsedGames[i])
                    }
                    statusMessage = parsedGames.length + " games found"
                } catch(e) {
                    console.error("DMS-Lutris: Error parsing JSON: " + e)
                    statusMessage = "Error parsing game list"
                }
            },
            20000
        )
    }

    function launchGame(gameId, slug) {
        console.log("DMS-Lutris: Launching " + slug)
        // Use sh -c to detach and run independently
        Proc.runCommand(
            "lutris-launch",
            ["sh", "-c", "/usr/bin/lutris lutris:rungame/" + slug + " &"],
            null,
            0
        )
        if (root.popoutProxy) root.popoutProxy.close()
    }

    horizontalBarPill: Component {
        DankIcon {
            name: "sports_esports"
            size: Theme.iconSizeSmall
            color: Theme.primary
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "sports_esports"
            size: Theme.iconSizeSmall
            color: Theme.primary
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    popoutContent: Component {
        FocusScope {
            width: parent ? parent.width : 0
            implicitHeight: mainContent.implicitHeight

            PopoutComponent {
                id: mainContent
                width: parent.width
                headerText: "Lutris Games"
                detailsText: root.statusMessage
                showCloseButton: false

                Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    Rectangle {
                        width: parent.width
                        height: Math.min(500, gamesGrid.contentHeight)
                        color: "transparent"
                        clip: true
                        visible: !root.isLoading && gamesModel.count > 0

                        GridView {
                            id: gamesGrid
                            anchors.fill: parent
                            model: gamesModel
                            cellWidth: parent.width / 4
                            cellHeight: 220
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Item {
                                width: gamesGrid.cellWidth
                                height: gamesGrid.cellHeight

                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - Theme.spacingS
                                    spacing: Theme.spacingXS

                                    Rectangle {
                                        id: coverContainer
                                        width: parent.width
                                        height: 180
                                        color: Theme.surfaceContainer
                                        radius: Theme.roundness === "ROUND_FULL" ? 12 : (Theme.roundness === "ROUND_TWELVE" ? 12 : (Theme.roundness === "ROUND_EIGHT" ? 8 : 4))
                                        clip: true

                                        Image {
                                            id: coverImage
                                            anchors.fill: parent
                                            source: model.coverPath ? "file://" + model.coverPath : ""
                                            fillMode: Image.PreserveAspectCrop
                                            visible: model.coverPath
                                        }

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: "image"
                                            size: 32
                                            color: Theme.surfaceVariantText
                                            visible: !model.coverPath
                                        }

                                        // Play button as an icon in the bottom right
                                        DankButton {
                                            width: 36
                                            height: 36
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.margins: Theme.spacingS
                                            iconName: "play_arrow"
                                            backgroundColor: Theme.primary
                                            textColor: Theme.onPrimary
                                            onClicked: root.launchGame(model.id, model.slug)
                                            
                                            radius: width / 2
                                        }
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: model.name || model.slug
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }

                            ScrollIndicator.vertical: ScrollIndicator { }
                        }
                    }

                    StyledText {
                        text: "Loading..."
                        visible: root.isLoading
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        text: "No games found."
                        visible: !root.isLoading && gamesModel.count === 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    popoutWidth: 600
}
