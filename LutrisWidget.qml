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
    property bool blacklistOnly: false

    property int sortMode: pluginData.sortMode ?? 0
    property var favorites: pluginData.favorites ?? []
    property var playCounts: pluginData.playCounts ?? {}
    property var blacklist: pluginData.blacklist ?? []

    onPluginDataChanged: {
        if (pluginData.blacklist !== undefined) {
            blacklist = pluginData.blacklist
            updateFilteredModel()
        }
    }

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
                    var gamesListForSettings = []
                    for (var i = 0; i < parsedGames.length; i++) {
                        gamesModel.append(parsedGames[i])
                        gamesListForSettings.push({
                            "name": parsedGames[i].name,
                            "slug": parsedGames[i].slug
                        })
                    }
                    // Save full list for Settings UI
                    pluginService?.savePluginData(pluginId, "allGames", gamesListForSettings)
                    
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
        console.log("DMS-Lutris: Updating filtered model. Blacklist: " + JSON.stringify(root.blacklist))
        filteredGamesModel.clear()
        var query = searchQuery.toLowerCase().trim()
        
        var currentBlacklist = root.blacklist || []
        var blackSet = new Set()
        for (var b = 0; b < currentBlacklist.length; b++) {
            blackSet.add(currentBlacklist[b])
        }

        for (var i = 0; i < gamesModel.count; i++) {
            var game = gamesModel.get(i)
            var isBlacklisted = blackSet.has(game.slug)

            if (blacklistOnly) {
                if (!isBlacklisted) continue;
            } else {
                if (isBlacklisted) continue;
            }

            var matchesSearch = query === "" || (game.name && game.name.toLowerCase().includes(query))
            var matchesFavorite = !favoriteOnly || root.isFavorite(game.slug)
            if (matchesSearch && matchesFavorite) {
                // Create a fresh object to avoid QML reference issues
                filteredGamesModel.append({
                    "id": game.id,
                    "name": game.name,
                    "slug": game.slug,
                    "coverPath": game.coverPath,
                    "isVirtual": false,
                    "isBlacklisted": isBlacklisted
                })
            }
        }
        
        console.log("DMS-Lutris: Filtered model updated. Count: " + filteredGamesModel.count)
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
            pluginService?.savePluginData(pluginId, "blacklist", blacklist)
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
            // If adding to favorites, remove from blacklist automatically
            var newBlacklist = (root.blacklist || []).slice()
            var bIdx = newBlacklist.indexOf(slug)
            if (bIdx >= 0) {
                newBlacklist.splice(bIdx, 1)
                root.blacklist = newBlacklist
            }
        }
        favorites = newFavs
        saveStats()
        updateFilteredModel()
    }

    function isFavorite(slug) {
        return favorites.indexOf(slug) >= 0
    }

    function toggleBlacklist(slug) {
        console.log("DMS-Lutris: Toggling blacklist for: " + slug)
        var newBlacklist = (root.blacklist || []).slice()
        var idx = newBlacklist.indexOf(slug)
        if (idx >= 0) {
            console.log("DMS-Lutris: Removing from blacklist")
            newBlacklist.splice(idx, 1)
        } else {
            console.log("DMS-Lutris: Adding to blacklist")
            newBlacklist.push(slug)
        }
        root.blacklist = newBlacklist
        saveStats()
        updateFilteredModel()
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
                            width: parent.width - 36 - 36 - 36 - 36 - 36 - Theme.spacingS * 5
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
                                if (root.favoriteOnly) root.blacklistOnly = false
                                root.updateFilteredModel()
                            }
                        }

                        DankButton {
                            id: blacklistOnlyButton
                            width: 36
                            height: parent.height
                            iconName: "visibility_off"
                            backgroundColor: root.blacklistOnly ? Theme.error : Theme.surfaceContainerHigh
                            textColor: root.blacklistOnly ? Theme.onPrimary : Theme.surfaceText
                            onClicked: {
                                root.blacklistOnly = !root.blacklistOnly
                                if (root.blacklistOnly) root.favoriteOnly = false
                                root.updateFilteredModel()
                            }
                        }

                        DankButton {
                            id: settingsButton
                            width: 36
                            height: parent.height
                            iconName: "settings"
                            backgroundColor: Theme.surfaceContainerHigh
                            textColor: Theme.surfaceText
                            onClicked: pluginService.showPluginSettings(root.pluginId)
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
                                        scale: clickAnimation.running ? 0.95 : 1.0

                                        Behavior on opacity {
                                            NumberAnimation { duration: 300 }
                                        }

                                        Behavior on scale {
                                            NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                                        }

                                        SequentialAnimation {
                                            id: clickAnimation
                                            NumberAnimation { target: coverContainer; property: "scale"; to: 0.95; duration: 50 }
                                            NumberAnimation { target: coverContainer; property: "scale"; to: 1.0; duration: 150 }
                                        }

                                        SequentialAnimation {
                                            running: model.id === root.launchingId
                                            loops: Animation.Infinite
                                            NumberAnimation { target: coverContainer; property: "opacity"; from: 1.0; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                            NumberAnimation { target: coverContainer; property: "opacity"; from: 0.8; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                                        }

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
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: (root.isLaunching && !model.isVirtual) ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            enabled: !root.isLaunching || (model.isVirtual && !root.isLaunching) // Disable during launch

                                            onClicked: (mouse) => {
                                                if (root.isLaunching) return;
                                                
                                                clickAnimation.start()

                                                if (model.isVirtual) {
                                                    if (mouse.button === Qt.LeftButton) {
                                                        Proc.runCommand("lutris-open", ["sh", "-c", "nohup /usr/bin/lutris > /dev/null 2>&1 &"], function() {}, 0)
                                                    }
                                                    return
                                                }

                                                if (mouse.button === Qt.LeftButton) {
                                                    root.launchGame(model.id, model.slug)
                                                } else if (mouse.button === Qt.RightButton) {
                                                    statsTooltip.targetSlug = model.slug
                                                    statsTooltip.targetName = model.name || model.slug
                                                    statsTooltip.targetIsBlacklisted = model.isBlacklisted
                                                    statsTooltip.visible = true
                                                }
                                            }

                                            ToolTip {
                                                id: statsTooltip
                                                property string targetSlug: ""
                                                property string targetName: ""
                                                property bool targetIsBlacklisted: false
                                                
                                                delay: 0
                                                timeout: 5000
                                                visible: false
                                                
                                                contentItem: Column {
                                                    spacing: 8
                                                    StyledText {
                                                        text: statsTooltip.targetName
                                                        font.bold: true
                                                        color: Theme.primary
                                                    }
                                                    StyledText {
                                                        text: "Play count: " + (root.playCounts[statsTooltip.targetSlug]?.count || 0)
                                                        font.pixelSize: Theme.fontSizeSmall
                                                    }
                                                    StyledText {
                                                        text: "Last played: " + (root.playCounts[statsTooltip.targetSlug]?.lastPlayed ? new Date(root.playCounts[statsTooltip.targetSlug].lastPlayed).toLocaleString() : "Never")
                                                        font.pixelSize: Theme.fontSizeSmall
                                                    }
                                                    
                                                    Item { width: 1; height: 4 }
                                                    
                                                    DankButton {
                                                        width: parent.width
                                                        height: 32
                                                        text: statsTooltip.targetIsBlacklisted ? "Unhide Game" : "Hide Game"
                                                        iconName: statsTooltip.targetIsBlacklisted ? "visibility" : "block"
                                                        backgroundColor: Theme.surfaceContainerHigh
                                                        textColor: statsTooltip.targetIsBlacklisted ? Theme.primary : Theme.error
                                                        enabled: statsTooltip.targetIsBlacklisted || !root.isFavorite(statsTooltip.targetSlug)
                                                        onClicked: {
                                                            statsTooltip.visible = false
                                                            root.toggleBlacklist(statsTooltip.targetSlug)
                                                        }
                                                    }
                                                    
                                                    StyledText {
                                                        visible: !statsTooltip.targetIsBlacklisted && root.isFavorite(statsTooltip.targetSlug)
                                                        text: "Cannot hide favorites"
                                                        font.pixelSize: 10
                                                        color: Theme.error
                                                        horizontalAlignment: Text.AlignHCenter
                                                        width: parent.width
                                                    }
                                                }

                                                background: Rectangle {
                                                    color: Theme.surfaceContainerHighest
                                                    radius: 8
                                                    border.color: Theme.surfaceVariant
                                                }
                                            }
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
                                            enabled: !root.isLaunching
                                            onClicked: root.toggleFavorite(model.slug)
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
