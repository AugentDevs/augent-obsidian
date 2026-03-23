import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var exitTimer: DispatchSourceTimer?

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        processFiles(filenames)
        scheduleExit()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if self?.exitTimer == nil { exit(0) }
        }
    }

    func scheduleExit() {
        exitTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1.5)
        t.setEventHandler { exit(0) }
        t.resume()
        exitTimer = t
    }
}

func processFiles(_ files: [String]) {
    let vault = "VAULT_PATH_HERE"
    let extDir = vault + "/External Files"
    let mapFile = vault + "/.obsidian/hardlink-map.txt"
    let fm = FileManager.default

    try? fm.createDirectory(atPath: extDir, withIntermediateDirectories: true)
    if !fm.fileExists(atPath: mapFile) { fm.createFile(atPath: mapFile, contents: nil) }

    for filepath in files {
        var target = filepath

        if !filepath.hasPrefix(vault) {
            let attrs = try? fm.attributesOfItem(atPath: filepath)
            let inode = (attrs?[.systemFileNumber] as? UInt64) ?? 0
            target = ""
            var linkType = "hardlink"
            var newlyLinked = false

            let mapContent = readMapLocked(mapFile)
            let prefix = filepath + "|"
            for line in mapContent.components(separatedBy: "\n") {
                if line.hasPrefix(prefix) {
                    let parts = String(line.dropFirst(prefix.count)).components(separatedBy: "|")
                    let mapped = parts[0]
                    if fm.fileExists(atPath: mapped) {
                        if parts.count > 1 && parts[1] == "symlink" {
                            target = mapped
                            linkType = "symlink"
                        } else {
                            let mAttrs = try? fm.attributesOfItem(atPath: mapped)
                            let mInode = (mAttrs?[.systemFileNumber] as? UInt64) ?? 0
                            if mInode == inode { target = mapped }
                        }
                    }
                    break
                }
            }

            if target.isEmpty {
                let fname = (filepath as NSString).lastPathComponent
                let quickPath = extDir + "/" + fname
                if fm.fileExists(atPath: quickPath) {
                    let qAttrs = try? fm.attributesOfItem(atPath: quickPath)
                    let qInode = (qAttrs?[.systemFileNumber] as? UInt64) ?? 0
                    if qInode == inode { target = quickPath }
                }
            }

            if target.isEmpty {
                let fname = (filepath as NSString).lastPathComponent
                var linkPath = extDir + "/" + fname

                if fm.fileExists(atPath: linkPath) {
                    let existingAttrs = try? fm.attributesOfItem(atPath: linkPath)
                    let existingInode = (existingAttrs?[.systemFileNumber] as? UInt64) ?? 0
                    if existingInode != inode {
                        let dirName = ((filepath as NSString).deletingLastPathComponent as NSString).lastPathComponent
                        let base = (fname as NSString).deletingPathExtension
                        let ext = (fname as NSString).pathExtension
                        if ext.isEmpty {
                            linkPath = extDir + "/" + base + " (" + dirName + ")"
                        } else {
                            linkPath = extDir + "/" + base + " (" + dirName + ")." + ext
                        }
                    }
                }

                unlink(linkPath)

                let linkResult = link(filepath, linkPath)
                if linkResult != 0 {
                    symlink(filepath, linkPath)
                    linkType = "symlink"
                }

                target = linkPath
                newlyLinked = true
            }

            let mapSuffix = linkType == "symlink" ? "|symlink" : ""
            writeMapEntryLocked(mapFile, original: filepath, target: target, suffix: mapSuffix)

            if newlyLinked { Thread.sleep(forTimeInterval: 0.3) }
        }

        if let encoded = target.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) {
            let urlStr = "obsidian://open?path=" + encoded
            if let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

func readMapLocked(_ path: String) -> String {
    let fd = open(path, O_RDONLY)
    guard fd >= 0 else { return "" }
    defer { close(fd) }
    flock(fd, LOCK_SH)
    defer { flock(fd, LOCK_UN) }
    let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

func writeMapEntryLocked(_ path: String, original: String, target: String, suffix: String) {
    let fd = open(path, O_RDWR | O_CREAT, 0o644)
    guard fd >= 0 else { return }
    flock(fd, LOCK_EX)

    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
    let data = handle.readDataToEndOfFile()
    let content = String(data: data, encoding: .utf8) ?? ""

    let prefix = original + "|"
    var lines = content.components(separatedBy: "\n")
        .filter { !$0.isEmpty && !$0.hasPrefix(prefix) }
    lines.append(original + "|" + target + suffix)

    let newContent = lines.joined(separator: "\n") + "\n"
    handle.seek(toFileOffset: 0)
    handle.write(newContent.data(using: .utf8)!)
    handle.truncateFile(atOffset: UInt64(newContent.utf8.count))

    flock(fd, LOCK_UN)
    close(fd)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
