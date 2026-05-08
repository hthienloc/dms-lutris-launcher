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

    property int launchingId: -1
    readonly property bool isLaunching: launchingId !== -1

    Component.onCompleted: {
        console.log("DMS-Lutris: Plugin initialized")
        fetchGames()
    }

    ListModel {
        id: gamesModel
    }

    ListModel {
        id: filteredGamesModel
    }

    property string searchQuery: ""
    property string filteredStatus: ""
    property bool favoriteOnly: false

    property int sortMode: pluginData.sortMode ?? 0
    property var favorites: pluginData.favorites ?? []
    property var playCounts: pluginData.playCounts ?? {}

    readonly property var sortModes: [
        { label: "Name", icon: "sort_by_alpha" },
        { label: "Recently Played", icon: "history" },
        { label: "Most Played", icon: "trending_up" }
    ]

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
                    
                    sortGames(parsedGames)

                    gamesModel.clear()
                    for (var i = 0; i < parsedGames.length; i++) {
                        gamesModel.append(parsedGames[i])
                    }
                    updateFilteredModel()
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
        if (isLaunching) return

        console.log("DMS-Lutris: Launching " + slug)
        launchingId = gameId

        var newCounts = Object.assign({}, playCounts)
        if (!newCounts[slug]) newCounts[slug] = { count: 0, lastPlayed: 0 }
        newCounts[slug].count++
        newCounts[slug].lastPlayed = Date.now()
        playCounts = newCounts
        saveStats()

        Proc.runCommand(
            "lutris-launch",
            ["sh", "-c", "/usr/bin/lutris lutris:rungame/" + slug + " &"],
            function(output, exitCode) {
                Qt.callLater(() => {
                    var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 20000; repeat: false; onTriggered: { parent.launchingId = -1; destroy(); } }', root);
                    timer.start();
                });
            },
            0
        )
    }

    function updateFilteredModel() {
        filteredGamesModel.clear()
        var query = searchQuery.toLowerCase().trim()
        for (var i = 0; i < gamesModel.count; i++) {
            var game = gamesModel.get(i)
            var matchesSearch = query === "" || (game.name && game.name.toLowerCase().includes(query))
            var matchesFavorite = !favoriteOnly || root.isFavorite(game.slug)
            if (matchesSearch && matchesFavorite) {
                // Create a fresh object to avoid QML reference issues
                filteredGamesModel.append({
                    "id": game.id,
                    "name": game.name,
                    "slug": game.slug,
                    "coverPath": game.coverPath,
                    "isVirtual": false
                })
            }
        }
        
        // Add virtual card at the end
        if (query === "") {
            filteredGamesModel.append({
                "id": -2,
                "name": "Add Games",
                "slug": "lutris-main",
                "isVirtual": true,
                "coverPath": ""
            })
        }

        filteredStatus = query === "" ? "" : filteredGamesModel.count + " of " + gamesModel.count + " games"
    }

    function onSearchTextChanged(text) {
        searchQuery = text
        updateFilteredModel()
    }

    function saveStats() {
        try {
            pluginService?.savePluginData(pluginId, "favorites", favorites)
            pluginService?.savePluginData(pluginId, "playCounts", playCounts)
            pluginService?.savePluginData(pluginId, "sortMode", sortMode)
        } catch(e) {
            console.log("DMS-Lutris: Failed to save stats", e)
        }
    }

    function sortGames(games) {
        var favSet = new Set(favorites)
        if (sortMode === 0) {
            games.sort((a, b) => {
                var aFav = favSet.has(a.slug) ? 0 : 1
                var bFav = favSet.has(b.slug) ? 0 : 1
                if (aFav !== bFav) return aFav - bFav
                return (a.name || "").localeCompare(b.name || "")
            })
        } else if (sortMode === 1) {
            games.sort((a, b) => {
                var aFav = favSet.has(a.slug) ? 0 : 1
                var bFav = favSet.has(b.slug) ? 0 : 1
                if (aFav !== bFav) return aFav - bFav
                var aTime = (playCounts[a.slug]?.lastPlayed || 0)
                var bTime = (playCounts[b.slug]?.lastPlayed || 0)
                return bTime - aTime
            })
        } else if (sortMode === 2) {
            games.sort((a, b) => {
                var aFav = favSet.has(a.slug) ? 0 : 1
                var bFav = favSet.has(b.slug) ? 0 : 1
                if (aFav !== bFav) return aFav - bFav
                var aCount = playCounts[a.slug]?.count || 0
                var bCount = playCounts[b.slug]?.count || 0
                return bCount - aCount
            })
        }
    }

    function toggleFavorite(slug) {
        var newFavs = favorites.slice()
        var idx = newFavs.indexOf(slug)
        if (idx >= 0) {
            newFavs.splice(idx, 1)
        } else {
            newFavs.push(slug)
        }
        favorites = newFavs
        saveStats()
    }

    function isFavorite(slug) {
        return favorites.indexOf(slug) >= 0
    }

    function sortGamesInternal() {
        var games = []
        for (var i = 0; i < gamesModel.count; i++) {
            var g = gamesModel.get(i)
            games.push({
                "id": g.id,
                "name": g.name,
                "slug": g.slug,
                "coverPath": g.coverPath
            })
        }
        sortGames(games)
        gamesModel.clear()
        for (var j = 0; j < games.length; j++) {
            gamesModel.append(games[j])
        }
        updateFilteredModel()
    }

    function cycleSortMode() {
        sortMode = (sortMode + 1) % sortModes.length
        saveStats()
        sortGamesInternal()
    }

    horizontalBarPill: Component {
        DankIcon {
            name: (root.isLaunching || root.isLoading) ? "refresh" : "sports_esports"
            size: Theme.iconSizeSmall
            color: (root.isLaunching || root.isLoading) ? Theme.warning : Theme.primary
            anchors.verticalCenter: parent.verticalCenter
            
            rotation: (root.isLaunching || root.isLoading) ? 0 : 0 // Placeholder to trigger binding if needed

            NumberAnimation on rotation {
                from: 0; to: 360; duration: 1000
                loops: Animation.Infinite
                running: root.isLaunching || root.isLoading
            }

            Behavior on rotation {
                enabled: !root.isLaunching && !root.isLoading
                NumberAnimation { duration: 300; easing.type: Easing.OutQuad }
            }
            
            onRotationChanged: {
                if (!root.isLaunching && !root.isLoading && rotation !== 0) {
                    rotation = 0
                }
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: (root.isLaunching || root.isLoading) ? "refresh" : "sports_esports"
            size: Theme.iconSizeSmall
            color: (root.isLaunching || root.isLoading) ? Theme.warning : Theme.primary
            anchors.horizontalCenter: parent.horizontalCenter

            NumberAnimation on rotation {
                from: 0; to: 360; duration: 1000
                loops: Animation.Infinite
                running: root.isLaunching || root.isLoading
            }

            Behavior on rotation {
                enabled: !root.isLaunching && !root.isLoading
                NumberAnimation { duration: 300; easing.type: Easing.OutQuad }
            }
            
            onRotationChanged: {
                if (!root.isLaunching && !root.isLoading && rotation !== 0) {
                    rotation = 0
                }
            }
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
                detailsText: root.isLaunching ? "Launching game..." : root.statusMessage
                showCloseButton: false

                Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        height: 44
                        spacing: Theme.spacingS

                        DankTextField {
                            id: searchField
                            width: parent.width - 36 - 36 - 36 - Theme.spacingS * 3
                            height: parent.height
                            leftIconName: "search"
                            placeholderText: "Search games..."
                            backgroundColor: Theme.surfaceVariant
                            normalBorderColor: Theme.surfaceContainerHigh
                            onTextEdited: root.onSearchTextChanged(text)
                        }

                        DankButton {
                            id: sortButton2
                            width: 36
                            height: parent.height
                            iconName: sortModes[sortMode].icon
                            backgroundColor: Theme.surfaceContainerHigh
                            textColor: Theme.surfaceText
                            onClicked: root.cycleSortMode()
                        }

                        DankButton {
                            id: favoriteOnlyButton
                            width: 36
                            height: parent.height
                            iconName: "star"
                            backgroundColor: root.favoriteOnly ? Theme.warning : Theme.surfaceContainerHigh
                            textColor: root.favoriteOnly ? Theme.onPrimary : Theme.surfaceText
                            onClicked: {
                                root.favoriteOnly = !root.favoriteOnly
                                root.updateFilteredModel()
                            }
                        }

                        DankButton {
                            id: refreshButton
                            width: 36
                            height: parent.height
                            iconName: "refresh"
                            backgroundColor: Theme.surfaceContainerHigh
                            textColor: root.isLoading ? Theme.surfaceVariantText : Theme.surfaceText
                            onClicked: root.fetchGames()

                            SequentialAnimation on rotation {
                                running: root.isLoading
                                loops: Animation.Infinite
                                NumberAnimation {
                                    from: 0; to: 360
                                    duration: 1000
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.min(500, gamesGrid.contentHeight)
                        color: "transparent"
                        clip: true
                        visible: !root.isLoading && filteredGamesModel.count > 0

                        GridView {
                            id: gamesGrid
                            anchors.fill: parent
                            model: filteredGamesModel
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
                                        opacity: (root.isLaunching && model.id !== root.launchingId) ? 0.5 : 1.0

                                        Image {
                                            id: coverImage
                                            anchors.fill: parent
                                            source: (model.coverPath && !model.isVirtual) ? "file://" + model.coverPath : ""
                                            fillMode: Image.PreserveAspectCrop
                                            visible: model.coverPath && !model.isVirtual
                                        }

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: model.isVirtual ? "add" : "image"
                                            size: 32
                                            color: Theme.surfaceVariantText
                                            visible: !model.coverPath || model.isVirtual
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            visible: model.isVirtual
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Proc.runCommand("lutris-open", ["sh", "-c", "nohup /usr/bin/lutris > /dev/null 2>&1 &"], function() {}, 0)
                                        }

                                        DankButton {
                                            width: 32
                                            height: 32
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.margins: Theme.spacingS
                                            iconName: root.isFavorite(model.slug) ? "star" : "star_border"
                                            backgroundColor: root.isFavorite(model.slug) ? Theme.warning : Theme.surfaceContainerHigh
                                            textColor: root.isFavorite(model.slug) ? Theme.onPrimary : Theme.surfaceVariantText
                                            radius: width / 2
                                            visible: !model.isVirtual
                                            onClicked: root.toggleFavorite(model.slug)
                                        }

                                        DankButton {
                                            width: 36
                                            height: 36
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.margins: Theme.spacingS
                                            iconName: model.id === root.launchingId ? "refresh" : "play_arrow"
                                            backgroundColor: model.id === root.launchingId ? Theme.warning : Theme.primary
                                            textColor: Theme.onPrimary
                                            opacity: root.isLaunching && model.id !== root.launchingId ? 0.5 : 1.0
                                            radius: width / 2
                                            visible: !model.isVirtual
                                            onClicked: root.launchGame(model.id, model.slug)

                                            SequentialAnimation on rotation {
                                                running: model.id === root.launchingId
                                                loops: Animation.Infinite
                                                NumberAnimation {
                                                    from: rotation
                                                    to: rotation + 360
                                                    duration: 1000
                                                }
                                            }
                                            Behavior on rotation {
                                                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                                            }
                                        }
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: model.name || model.slug
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: (root.isLaunching && model.id !== root.launchingId) ? Theme.surfaceVariantText : Theme.surfaceText
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
                        text: root.searchQuery !== "" ? "No games match your search." : "No games found."
                        visible: !root.isLoading && filteredGamesModel.count === 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    popoutWidth: 600
}
