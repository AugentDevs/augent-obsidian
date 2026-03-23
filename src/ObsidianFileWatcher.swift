import Cocoa

let vault = "VAULT_PATH_HERE"
let mapFile = vault + "/.obsidian/hardlink-map.txt"
let fm = FileManager.default

class WatcherDelegate: NSObject, NSApplicationDelegate {
    var mapSource: DispatchSourceFileSystemObject?
    var timer: DispatchSourceTimer?
    var mapFd: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? fm.createDirectory(atPath: vault + "/.obsidian", withIntermediateDirectories: true)
        if !fm.fileExists(atPath: mapFile) { fm.createFile(atPath: mapFile, contents: nil) }
        watchMapFile()
        scheduleCheck()
    }

    func watchMapFile() {
        if mapFd >= 0 { close(mapFd) }
        mapFd = open(mapFile, O_EVTONLY)
        guard mapFd >= 0 else { return }

        mapSource?.cancel()
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: mapFd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self?.mapSource?.cancel()
                self?.mapSource = nil
                if self?.mapFd ?? -1 >= 0 { close(self!.mapFd); self?.mapFd = -1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.watchMapFile()
                }
            }
        }
        source.setCancelHandler { [weak self] in
            if self?.mapFd ?? -1 >= 0 { close(self!.mapFd); self?.mapFd = -1 }
        }
        source.resume()
        mapSource = source
    }

    func scheduleCheck() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 2, repeating: 2.0)
        t.setEventHandler { [weak self] in
            self?.checkAndRelink()
        }
        t.resume()
        timer = t
    }

    func checkAndRelink() {
        let fd = open(mapFile, O_RDONLY)
        guard fd >= 0 else { return }
        flock(fd, LOCK_SH)
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        flock(fd, LOCK_UN)
        close(fd)

        let content = String(data: data, encoding: .utf8) ?? ""
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        if lines.isEmpty { return }

        var updatedLines: [String] = []
        var changed = false

        for line in lines {
            let firstPipe = line.firstIndex(of: "|")
            guard let pipeIdx = firstPipe else { updatedLines.append(line); continue }

            let orig = String(line[line.startIndex..<pipeIdx])
            let rest = String(line[line.index(after: pipeIdx)...])
            let restParts = rest.components(separatedBy: "|")
            var vfile = restParts[0]
            let isSymlink = restParts.count > 1 && restParts[1] == "symlink"

            if isSymlink { updatedLines.append(line); continue }
            guard fm.fileExists(atPath: orig) else { updatedLines.append(line); continue }

            if !fm.fileExists(atPath: vfile) {
                let fname = (vfile as NSString).lastPathComponent
                let pipe = Pipe()
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/find")
                proc.arguments = [vault, "-not", "-path", "*/.obsidian/*", "-name", fname, "-type", "f", "-print", "-quit"]
                proc.standardOutput = pipe
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
                proc.waitUntilExit()
                let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !found.isEmpty {
                    vfile = found
                    changed = true
                } else {
                    updatedLines.append(line)
                    continue
                }
            }

            let origAttrs = try? fm.attributesOfItem(atPath: orig)
            let vfileAttrs = try? fm.attributesOfItem(atPath: vfile)
            let origInode = (origAttrs?[.systemFileNumber] as? UInt64) ?? 0
            let vfileInode = (vfileAttrs?[.systemFileNumber] as? UInt64) ?? 0

            if origInode != vfileInode {
                let origMod = (origAttrs?[.modificationDate] as? Date) ?? .distantPast
                let vfileMod = (vfileAttrs?[.modificationDate] as? Date) ?? .distantPast
                if vfileMod > origMod {
                    unlink(orig)
                    link(vfile, orig)
                } else {
                    unlink(vfile)
                    link(orig, vfile)
                }
                changed = true
            }
            updatedLines.append(orig + "|" + vfile)
        }

        if changed {
            let wfd = open(mapFile, O_RDWR | O_CREAT, 0o644)
            guard wfd >= 0 else { return }
            flock(wfd, LOCK_EX)
            let handle = FileHandle(fileDescriptor: wfd, closeOnDealloc: false)
            let newContent = updatedLines.joined(separator: "\n") + "\n"
            handle.seek(toFileOffset: 0)
            handle.write(newContent.data(using: .utf8)!)
            handle.truncateFile(atOffset: UInt64(newContent.utf8.count))
            flock(wfd, LOCK_UN)
            close(wfd)
        }
    }
}

let app = NSApplication.shared
let delegate = WatcherDelegate()
app.delegate = delegate
app.run()
