import Foundation
import SwiftRs
import Tauri
import UIKit
import WebKit

class PathArgs: Decodable {
  let path: String
}

class StartArgs: Decodable {
  let url: String
  let path: String
}

/// One background session for every model file. The system keeps its downloads going while the app
/// is suspended (spec 021 C4); creating the session again with the same identifier, at the next
/// launch, reattaches to them and delivers whatever finished meanwhile.
final class Downloads: NSObject, URLSessionDownloadDelegate {
  static let shared = Downloads()

  struct Entry {
    var state = "running"
    var done: Int64 = 0
    var total: Int64 = 0
    var error: String?
  }

  private let lock = NSLock()
  private var entries: [String: Entry] = [:]

  lazy var session: URLSession = {
    let c = URLSessionConfiguration.background(withIdentifier: "ph.intportal.models")
    c.isDiscretionary = false
    c.sessionSendsLaunchEvents = true
    return URLSession(configuration: c, delegate: self, delegateQueue: nil)
  }()

  private func update(_ path: String, _ f: (inout Entry) -> Void) {
    lock.lock()
    var e = entries[path] ?? Entry()
    f(&e)
    entries[path] = e
    lock.unlock()
  }

  /// What was kept of a stopped download, for `downloadTask(withResumeData:)`.
  private func resumeFile(_ path: String) -> URL { URL(fileURLWithPath: path + ".resume") }

  func start(_ url: URL, _ path: String) {
    update(path) { $0 = Entry() } // "running" at once, so a status read right after doesn't start a second one
    session.getAllTasks { tasks in
      if tasks.contains(where: { $0.taskDescription == path && $0.state == .running }) { return }
      let task: URLSessionDownloadTask
      if let data = try? Data(contentsOf: self.resumeFile(path)) {
        task = self.session.downloadTask(withResumeData: data)
        try? FileManager.default.removeItem(at: self.resumeFile(path))
      } else {
        task = self.session.downloadTask(with: url)
      }
      task.taskDescription = path
      task.resume()
    }
  }

  func status(_ path: String) -> [String: Any] {
    lock.lock()
    let e = entries[path]
    lock.unlock()
    guard let e = e else {
      // Finished while the app was away, before this launch asked.
      return ["state": FileManager.default.fileExists(atPath: path) ? "done" : "none"]
    }
    var out: [String: Any] = ["state": e.state, "done": e.done, "total": e.total]
    if let err = e.error { out["error"] = err }
    return out
  }

  func cancel(_ path: String) {
    update(path) { $0.state = "paused" }
    session.getAllTasks { tasks in
      for t in tasks where t.taskDescription == path {
        guard let d = t as? URLSessionDownloadTask else { t.cancel(); continue }
        d.cancel(byProducingResumeData: { data in
          if let data = data { try? data.write(to: self.resumeFile(path)) }
        })
      }
    }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
    guard let path = downloadTask.taskDescription else { return }
    update(path) {
      if $0.state != "paused" { $0.state = "running" }
      $0.done = totalBytesWritten
      $0.total = max(totalBytesExpectedToWrite, 0)
    }
  }

  /// The file must be moved before this returns: the system deletes it afterwards.
  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let path = downloadTask.taskDescription else { return }
    if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
      update(path) { $0.state = "failed"; $0.error = "http:\(http.statusCode)" }
      return
    }
    let dest = URL(fileURLWithPath: path)
    do {
      try? FileManager.default.removeItem(at: dest)
      try FileManager.default.moveItem(at: location, to: dest)
      // Models are big and rebuildable: never in the iCloud backup (ADR 0003).
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var d = dest
      try? d.setResourceValues(values)
      update(path) { $0.state = "done"; $0.done = $0.total }
    } catch {
      update(path) { $0.state = "failed"; $0.error = Downloads.code(error) }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let path = task.taskDescription, let error = error else { return }
    if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
      try? data.write(to: resumeFile(path))
    }
    update(path) {
      if $0.state == "paused" { return }
      $0.state = "failed"
      $0.error = Downloads.code(error)
    }
  }

  static func code(_ error: Error) -> String {
    let e = error as NSError
    if e.domain == NSPOSIXErrorDomain && e.code == Int(ENOSPC) { return "nospace" }
    if e.domain == NSCocoaErrorDomain && e.code == NSFileWriteOutOfSpaceError { return "nospace" }
    if e.domain == NSURLErrorDomain {
      switch e.code {
      case NSURLErrorCannotWriteToFile: return "nospace"
      case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
        NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
        NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed, NSURLErrorBackgroundSessionWasDisconnected:
        return "offline"
      default: break
      }
    }
    return e.localizedDescription
  }
}

class DownloadPlugin: Plugin {
  override func load(webview: WKWebView) {
    _ = Downloads.shared.session // reattach to downloads the system kept going
  }

  @objc public func space(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(PathArgs.self)
    let values = try URL(fileURLWithPath: args.path).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    invoke.resolve(["bytes": values.volumeAvailableCapacityForImportantUsage ?? 0])
  }

  @objc public func start(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(StartArgs.self)
    guard let url = URL(string: args.url) else { return invoke.reject("bad url") }
    Downloads.shared.start(url, args.path)
    invoke.resolve()
  }

  @objc public func status(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(PathArgs.self)
    invoke.resolve(Downloads.shared.status(args.path))
  }

  @objc public func cancel(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(PathArgs.self)
    Downloads.shared.cancel(args.path)
    invoke.resolve()
  }
}

@_cdecl("init_plugin_download")
func initPlugin() -> Plugin {
  return DownloadPlugin()
}
