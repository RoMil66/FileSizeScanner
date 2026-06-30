import Foundation

/// Information about known system/cache folders with cleanup tips
struct FolderInfo {
    let titleDE: String
    let titleEN: String
    let descriptionDE: String
    let descriptionEN: String
    let cleanupDE: String
    let cleanupEN: String
    let isDeletable: Bool
    
    var title: String { isGerman ? titleDE : titleEN }
    var description: String { isGerman ? descriptionDE : descriptionEN }
    var cleanup: String { isGerman ? cleanupDE : cleanupEN }
    
    private var isGerman: Bool {
        Locale.current.language.languageCode?.identifier == "de"
    }
}

/// Maps known system folder names/paths to info
enum SystemFolderInfo {
    
    /// Returns info for a folder if it's a known system/cache folder
    static func info(for name: String, path: String) -> FolderInfo? {
        // Check by full path components
        let lowerPath = path.lowercased()
        let lowerName = name.lowercased()
        
        // Time Machine
        if lowerName == ".mobilebackups" || lowerName == ".tm_snapshot" ||
           lowerName == "backups.backupdb" || lowerName == ".timemachine" ||
           lowerPath.contains("timemachine") || lowerPath.contains("mobilebackups") ||
           lowerName == "com.apple.timemachine" {
            return timeMachine
        }
        
        // Spotlight
        if lowerName == ".spotlight-v100" || lowerName == ".spotlight" ||
           lowerName == "com.apple.spotlight" {
            return spotlight
        }
        
        // fseventsd
        if lowerName == ".fseventsd" {
            return fseventsd
        }
        
        // Xcode DerivedData
        if lowerName == "deriveddata" && lowerPath.contains("xcode") ||
           lowerPath.contains("developer/xcode/deriveddata") {
            return xcodeDerivedData
        }
        
        // Xcode Archives
        if lowerName == "archives" && lowerPath.contains("xcode") {
            return xcodeArchives
        }
        
        // Xcode iOS DeviceSupport
        if lowerName == "devicesupport" && lowerPath.contains("xcode") {
            return xcodeDeviceSupport
        }
        
        // Xcode simulators
        if lowerName == "coresimulator" || (lowerName == "devices" && lowerPath.contains("coresimulator")) {
            return xcodeSimulators
        }
        
        // System Caches
        if lowerName == "caches" && (lowerPath.contains("/library/caches") || lowerPath.contains("~/library/caches")) {
            return libraryCaches
        }
        
        // Application Support
        if lowerName == "application support" && lowerPath.contains("/library/") {
            return applicationSupport
        }
        
        // Logs
        if lowerName == "logs" && lowerPath.contains("/library/") {
            return libraryLogs
        }
        
        // Trash
        if lowerName == ".trash" || lowerName == ".trashes" {
            return trash
        }
        
        // node_modules
        if lowerName == "node_modules" {
            return nodeModules
        }
        
        // .git
        if lowerName == ".git" {
            return gitFolder
        }
        
        // Docker
        if lowerName == "docker" && lowerPath.contains("/library/") ||
           lowerName == "docker.raw" || lowerName == "docker.qcow2" {
            return docker
        }
        
        // Homebrew
        if lowerName == "homebrew" || (lowerName == "cellar" && lowerPath.contains("homebrew")) {
            return homebrew
        }
        
        // Mail
        if lowerName == "mail" && lowerPath.contains("/library/") ||
           lowerName == "v10" && lowerPath.contains("mail") {
            return mail
        }
        
        // Photos Library
        if lowerName.hasSuffix(".photoslibrary") {
            return photosLibrary
        }
        
        // Music/GarageBand
        if lowerName == "garageband" || lowerName == "music" && lowerPath.contains("/library/") {
            return musicLibrary
        }
        
        // iCloud
        if lowerName == "mobile documents" || lowerName == "clouddocs" {
            return iCloud
        }
        
        // System Library (root)
        if path == "/Library" || path == "/System/Library" {
            return systemLibrary
        }
        
        // Parallels / VMs
        if lowerName.hasSuffix(".pvm") || lowerName == "parallels" ||
           lowerName == "virtual machines" || lowerName == "virtual machines.localized" {
            return virtualMachines
        }
        
        // swap
        if lowerName == "swapfile0" || lowerName == "swapfile1" ||
           lowerName == "sleepimage" || lowerPath.contains("/var/vm") {
            return swapFiles
        }
        
        // APFS snapshots
        if lowerName == ".vol" || lowerName == "com.apple.os.update-" {
            return apfsSnapshots
        }
        
        // Cookies
        if lowerName == "cookies" && lowerPath.contains("/library/") {
            return cookies
        }
        
        // WebKit / Safari cache
        if lowerName == "webkit" && lowerPath.contains("/library/") ||
           lowerName == "safari" && lowerPath.contains("/library/") {
            return safariCache
        }
        
        // Chrome
        if lowerName == "google" && lowerPath.contains("application support") ||
           lowerName == "chrome" {
            return chromeData
        }
        
        // Dropbox
        if lowerName == ".dropbox" || lowerName == "dropbox" {
            return dropbox
        }
        
        // OneDrive
        if lowerName.contains("onedrive") {
            return oneDrive
        }
        
        // Library top-level
        if lowerName == "library" && (path == "\(NSHomeDirectory())/Library" || path.hasSuffix("/Library")) {
            return userLibrary
        }
        
        return nil
    }
    
    // MARK: - Folder Definitions
    
    static let timeMachine = FolderInfo(
        titleDE: "Time Machine Backups",
        titleEN: "Time Machine Backups",
        descriptionDE: "Lokale Snapshots von Time Machine. macOS erstellt regelmäßig Schnappschüsse, auch wenn keine externe Backup-Platte angeschlossen ist.",
        descriptionEN: "Local Time Machine snapshots. macOS creates snapshots regularly, even without an external backup drive connected.",
        cleanupDE: "Terminal: sudo tmutil listlocalsnapshots / → sudo tmutil deletelocalsnapshots <datum>. Oder in Systemeinstellungen → Time Machine → Optionen verwalten.",
        cleanupEN: "Terminal: sudo tmutil listlocalsnapshots / → sudo tmutil deletelocalsnapshots <date>. Or manage in System Settings → Time Machine → Options.",
        isDeletable: false
    )
    
    static let spotlight = FolderInfo(
        titleDE: "Spotlight-Index",
        titleEN: "Spotlight Index",
        descriptionDE: "Suchindex von macOS Spotlight. Wird automatisch neu aufgebaut wenn gelöscht.",
        descriptionEN: "macOS Spotlight search index. Automatically rebuilt when deleted.",
        cleanupDE: "Terminal: sudo mdutil -E / (Index neu aufbauen). Normalerweise nicht nötig.",
        cleanupEN: "Terminal: sudo mdutil -E / (rebuild index). Usually not necessary.",
        isDeletable: false
    )
    
    static let fseventsd = FolderInfo(
        titleDE: "File System Events",
        titleEN: "File System Events",
        descriptionDE: "Protokoll aller Dateisystem-Änderungen. Wird von Time Machine und Spotlight verwendet.",
        descriptionEN: "Log of all filesystem changes. Used by Time Machine and Spotlight.",
        cleanupDE: "Nicht manuell löschen — wird vom System verwaltet.",
        cleanupEN: "Do not delete manually — managed by the system.",
        isDeletable: false
    )
    
    static let xcodeDerivedData = FolderInfo(
        titleDE: "Xcode Build-Daten",
        titleEN: "Xcode Build Data",
        descriptionDE: "Kompilierte Build-Produkte, Indices und Logs von Xcode. Kann sehr groß werden.",
        descriptionEN: "Compiled build products, indexes and logs from Xcode. Can grow very large.",
        cleanupDE: "Sicher löschbar! Xcode baut alles bei Bedarf neu. Xcode → Settings → Locations → DerivedData → Pfeil-Button. Oder: rm -rf ~/Library/Developer/Xcode/DerivedData",
        cleanupEN: "Safe to delete! Xcode rebuilds everything as needed. Xcode → Settings → Locations → DerivedData → arrow button. Or: rm -rf ~/Library/Developer/Xcode/DerivedData",
        isDeletable: true
    )
    
    static let xcodeArchives = FolderInfo(
        titleDE: "Xcode Archive",
        titleEN: "Xcode Archives",
        descriptionDE: "App-Archive für App Store Uploads und Ad-hoc-Distribution.",
        descriptionEN: "App archives for App Store uploads and ad-hoc distribution.",
        cleanupDE: "Alte Archive können in Xcode → Window → Organizer gelöscht werden. Nur aktuelle Versionen behalten.",
        cleanupEN: "Old archives can be deleted in Xcode → Window → Organizer. Keep only current versions.",
        isDeletable: true
    )
    
    static let xcodeDeviceSupport = FolderInfo(
        titleDE: "Xcode Device Support",
        titleEN: "Xcode Device Support",
        descriptionDE: "Debug-Symbole für jede iOS-Version die jemals per USB verbunden war. Pro Version ~2-5 GB.",
        descriptionEN: "Debug symbols for every iOS version connected via USB. ~2-5 GB per version.",
        cleanupDE: "Alte iOS-Versionen löschen die nicht mehr benötigt werden: rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport/<alte-version>",
        cleanupEN: "Delete old iOS versions no longer needed: rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport/<old-version>",
        isDeletable: true
    )
    
    static let xcodeSimulators = FolderInfo(
        titleDE: "iOS Simulatoren",
        titleEN: "iOS Simulators",
        descriptionDE: "Daten der iOS/iPadOS/watchOS Simulatoren inkl. installierter Apps und Caches.",
        descriptionEN: "iOS/iPadOS/watchOS simulator data including installed apps and caches.",
        cleanupDE: "Unbenutzte löschen: xcrun simctl delete unavailable. Alle Simulator-Inhalte: xcrun simctl erase all",
        cleanupEN: "Delete unused: xcrun simctl delete unavailable. Erase all content: xcrun simctl erase all",
        isDeletable: true
    )
    
    static let libraryCaches = FolderInfo(
        titleDE: "App-Caches",
        titleEN: "App Caches",
        descriptionDE: "Zwischengespeicherte Daten von Apps. Können nach dem Löschen von Apps übrig bleiben.",
        descriptionEN: "Cached data from applications. May remain after apps are deleted.",
        cleanupDE: "Einzelne App-Caches können meist gefahrlos gelöscht werden. Nicht den gesamten Caches-Ordner löschen!",
        cleanupEN: "Individual app caches can usually be safely deleted. Don't delete the entire Caches folder!",
        isDeletable: false
    )
    
    static let applicationSupport = FolderInfo(
        titleDE: "App-Einstellungen & Daten",
        titleEN: "App Settings & Data",
        descriptionDE: "Konfigurationsdaten, Datenbanken und Einstellungen von installierten Apps.",
        descriptionEN: "Configuration data, databases and settings from installed applications.",
        cleanupDE: "Vorsicht! Nur Ordner von bereits deinstallierten Apps löschen. Reste nach App-Löschung prüfen.",
        cleanupEN: "Caution! Only delete folders from already uninstalled apps. Check for remnants after app removal.",
        isDeletable: false
    )
    
    static let libraryLogs = FolderInfo(
        titleDE: "System- & App-Logs",
        titleEN: "System & App Logs",
        descriptionDE: "Protokolldateien von macOS und installierten Apps.",
        descriptionEN: "Log files from macOS and installed applications.",
        cleanupDE: "Alte Logs können gelöscht werden: Ordner öffnen und Dateien älter als 30 Tage entfernen.",
        cleanupEN: "Old logs can be deleted: open folder and remove files older than 30 days.",
        isDeletable: true
    )
    
    static let trash = FolderInfo(
        titleDE: "Papierkorb",
        titleEN: "Trash",
        descriptionDE: "Gelöschte Dateien die noch nicht endgültig entfernt wurden.",
        descriptionEN: "Deleted files that have not been permanently removed yet.",
        cleanupDE: "Rechtsklick auf Papierkorb im Dock → Papierkorb entleeren. Oder Finder → Papierkorb entleeren.",
        cleanupEN: "Right-click Trash in Dock → Empty Trash. Or Finder → Empty Trash.",
        isDeletable: true
    )
    
    static let nodeModules = FolderInfo(
        titleDE: "Node.js Abhängigkeiten",
        titleEN: "Node.js Dependencies",
        descriptionDE: "npm/yarn Pakete für ein JavaScript/TypeScript-Projekt. Kann hunderte MB pro Projekt sein.",
        descriptionEN: "npm/yarn packages for a JavaScript/TypeScript project. Can be hundreds of MB per project.",
        cleanupDE: "Sicher löschbar! Wird mit 'npm install' oder 'yarn install' neu heruntergeladen.",
        cleanupEN: "Safe to delete! Reinstall with 'npm install' or 'yarn install'.",
        isDeletable: true
    )
    
    static let gitFolder = FolderInfo(
        titleDE: "Git-Repository",
        titleEN: "Git Repository",
        descriptionDE: "Versionsverlauf des Projekts. Enthält alle Commits, Branches und History.",
        descriptionEN: "Version history of the project. Contains all commits, branches and history.",
        cleanupDE: "git gc --aggressive (komprimiert Repository). Oder große Dateien aus History entfernen mit git filter-branch.",
        cleanupEN: "git gc --aggressive (compresses repository). Or remove large files from history with git filter-branch.",
        isDeletable: false
    )
    
    static let docker = FolderInfo(
        titleDE: "Docker-Daten",
        titleEN: "Docker Data",
        descriptionDE: "Docker Images, Container und Volumes. Kann sehr groß werden.",
        descriptionEN: "Docker images, containers and volumes. Can grow very large.",
        cleanupDE: "docker system prune -a (entfernt unbenutzte Images/Container). Docker Desktop → Settings → Resources → Disk Image Size.",
        cleanupEN: "docker system prune -a (removes unused images/containers). Docker Desktop → Settings → Resources → Disk Image Size.",
        isDeletable: false
    )
    
    static let homebrew = FolderInfo(
        titleDE: "Homebrew Pakete",
        titleEN: "Homebrew Packages",
        descriptionDE: "Installierte Homebrew-Pakete und deren Abhängigkeiten.",
        descriptionEN: "Installed Homebrew packages and their dependencies.",
        cleanupDE: "brew cleanup (entfernt alte Versionen). brew autoremove (entfernt unbenutzte Abhängigkeiten).",
        cleanupEN: "brew cleanup (removes old versions). brew autoremove (removes unused dependencies).",
        isDeletable: false
    )
    
    static let mail = FolderInfo(
        titleDE: "Mail-Daten",
        titleEN: "Mail Data",
        descriptionDE: "Lokal gespeicherte E-Mails, Anhänge und Suchindex der Mail-App.",
        descriptionEN: "Locally stored emails, attachments and search index from Mail app.",
        cleanupDE: "In Mail.app: Postfach → Neu aufbauen. Große Anhänge in Mail suchen und E-Mails löschen.",
        cleanupEN: "In Mail.app: Mailbox → Rebuild. Search for large attachments in Mail and delete emails.",
        isDeletable: false
    )
    
    static let photosLibrary = FolderInfo(
        titleDE: "Fotos-Mediathek",
        titleEN: "Photos Library",
        descriptionDE: "Alle Fotos und Videos in der Apple Fotos App.",
        descriptionEN: "All photos and videos in the Apple Photos app.",
        cleanupDE: "Fotos App → Einstellungen → iCloud → Mac-Speicher optimieren (lädt Originale in iCloud hoch, spart lokal Platz).",
        cleanupEN: "Photos App → Settings → iCloud → Optimize Mac Storage (uploads originals to iCloud, saves local space).",
        isDeletable: false
    )
    
    static let musicLibrary = FolderInfo(
        titleDE: "Musik-Daten",
        titleEN: "Music Data",
        descriptionDE: "Lokal gespeicherte Musik, Podcasts und GarageBand-Projekte.",
        descriptionEN: "Locally stored music, podcasts and GarageBand projects.",
        cleanupDE: "Musik-App → Einstellungen → Downloads verwalten. GarageBand-Loops die nicht benötigt werden löschen.",
        cleanupEN: "Music App → Settings → Manage Downloads. Delete unused GarageBand loops.",
        isDeletable: false
    )
    
    static let iCloud = FolderInfo(
        titleDE: "iCloud Drive Daten",
        titleEN: "iCloud Drive Data",
        descriptionDE: "Lokal synchronisierte iCloud Drive Dateien.",
        descriptionEN: "Locally synced iCloud Drive files.",
        cleanupDE: "Systemeinstellungen → Apple ID → iCloud → Mac-Speicher optimieren aktivieren.",
        cleanupEN: "System Settings → Apple ID → iCloud → Optimize Mac Storage.",
        isDeletable: false
    )
    
    static let systemLibrary = FolderInfo(
        titleDE: "System-Bibliothek",
        titleEN: "System Library",
        descriptionDE: "Systemdateien von macOS. Nicht verändern!",
        descriptionEN: "macOS system files. Do not modify!",
        cleanupDE: "Nicht löschbar. macOS-Update oder Neuinstallation wenn zu groß.",
        cleanupEN: "Cannot be deleted. macOS update or reinstall if too large.",
        isDeletable: false
    )
    
    static let virtualMachines = FolderInfo(
        titleDE: "Virtuelle Maschinen",
        titleEN: "Virtual Machines",
        descriptionDE: "Parallels Desktop, VMware oder UTM VM-Images. Oft 20-100+ GB pro VM.",
        descriptionEN: "Parallels Desktop, VMware or UTM VM images. Often 20-100+ GB per VM.",
        cleanupDE: "Unbenutzte VMs in Parallels/VMware löschen. Snapshots in VMs aufräumen. VM-Festplatten komprimieren.",
        cleanupEN: "Delete unused VMs in Parallels/VMware. Clean up VM snapshots. Compact VM disks.",
        isDeletable: true
    )
    
    static let swapFiles = FolderInfo(
        titleDE: "Swap & Ruhezustand",
        titleEN: "Swap & Sleep Image",
        descriptionDE: "Virtueller Speicher (Swap) und Ruhezustand-Image. Größe abhängig vom RAM.",
        descriptionEN: "Virtual memory (swap) and sleep image. Size depends on RAM.",
        cleanupDE: "Wird vom System verwaltet. Neustart kann Swap reduzieren. sleepimage: sudo pmset hibernatemode 0",
        cleanupEN: "Managed by the system. Restart can reduce swap. sleepimage: sudo pmset hibernatemode 0",
        isDeletable: false
    )
    
    static let apfsSnapshots = FolderInfo(
        titleDE: "APFS Snapshots",
        titleEN: "APFS Snapshots",
        descriptionDE: "Automatische Dateisystem-Snapshots von macOS Updates und Time Machine.",
        descriptionEN: "Automatic filesystem snapshots from macOS updates and Time Machine.",
        cleanupDE: "Terminal: tmutil listlocalsnapshots / → tmutil deletelocalsnapshots <datum>",
        cleanupEN: "Terminal: tmutil listlocalsnapshots / → tmutil deletelocalsnapshots <date>",
        isDeletable: false
    )
    
    static let cookies = FolderInfo(
        titleDE: "Browser-Cookies",
        titleEN: "Browser Cookies",
        descriptionDE: "Cookies und Website-Daten von Safari und anderen Apps.",
        descriptionEN: "Cookies and website data from Safari and other apps.",
        cleanupDE: "Safari → Einstellungen → Datenschutz → Websitedaten verwalten → Alle entfernen.",
        cleanupEN: "Safari → Settings → Privacy → Manage Website Data → Remove All.",
        isDeletable: true
    )
    
    static let safariCache = FolderInfo(
        titleDE: "Safari-Cache",
        titleEN: "Safari Cache",
        descriptionDE: "Zwischengespeicherte Webseiten, Bilder und Daten von Safari.",
        descriptionEN: "Cached web pages, images and data from Safari.",
        cleanupDE: "Safari → Entwickler → Cache-Speicher leeren. Oder: Safari → Einstellungen → Datenschutz → Websitedaten verwalten.",
        cleanupEN: "Safari → Develop → Empty Caches. Or: Safari → Settings → Privacy → Manage Website Data.",
        isDeletable: true
    )
    
    static let chromeData = FolderInfo(
        titleDE: "Google Chrome Daten",
        titleEN: "Google Chrome Data",
        descriptionDE: "Profildaten, Cache und Erweiterungen von Google Chrome.",
        descriptionEN: "Profile data, cache and extensions from Google Chrome.",
        cleanupDE: "Chrome → Einstellungen → Datenschutz → Browserdaten löschen. Cache und Verlauf können gelöscht werden.",
        cleanupEN: "Chrome → Settings → Privacy → Clear browsing data. Cache and history can be cleared.",
        isDeletable: false
    )
    
    static let dropbox = FolderInfo(
        titleDE: "Dropbox-Daten",
        titleEN: "Dropbox Data",
        descriptionDE: "Lokal synchronisierte Dropbox-Dateien und Cache.",
        descriptionEN: "Locally synced Dropbox files and cache.",
        cleanupDE: "Dropbox-App → Einstellungen → Sync → Selektive Synchronisierung. Nur benötigte Ordner lokal behalten.",
        cleanupEN: "Dropbox App → Settings → Sync → Selective Sync. Only keep needed folders locally.",
        isDeletable: false
    )
    
    static let oneDrive = FolderInfo(
        titleDE: "OneDrive-Daten",
        titleEN: "OneDrive Data",
        descriptionDE: "Lokal synchronisierte OneDrive-Dateien.",
        descriptionEN: "Locally synced OneDrive files.",
        cleanupDE: "OneDrive → Einstellungen → Konto → Ordner auswählen. Dateien auf \"Nur online\" setzen (Rechtsklick → Speicherplatz freigeben).",
        cleanupEN: "OneDrive → Settings → Account → Choose Folders. Set files to 'Online Only' (right-click → Free Up Space).",
        isDeletable: false
    )
    
    static let userLibrary = FolderInfo(
        titleDE: "Benutzer-Bibliothek",
        titleEN: "User Library",
        descriptionDE: "Enthält App-Einstellungen, Caches, Mail, Logs und mehr. Versteckter macOS-Ordner.",
        descriptionEN: "Contains app settings, caches, mail, logs and more. Hidden macOS folder.",
        cleanupDE: "Unterordner einzeln prüfen: Caches, Logs und Application Support von deinstallierten Apps können gelöscht werden.",
        cleanupEN: "Check subfolders individually: Caches, Logs and Application Support from uninstalled apps can be deleted.",
        isDeletable: false
    )
}
