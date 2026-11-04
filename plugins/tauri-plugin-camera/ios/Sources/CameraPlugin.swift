import AVFoundation
import PhotosUI
import Tauri
import UIKit
import Vision

struct ReadArgs: Decodable {
  let text: Bool?
  let qr: Bool?
}

class CaptureArgs: Decodable {
  let source: String
  let read: ReadArgs?
  let saveTo: String?
}

struct CaptureResult: Encodable {
  var cancelled = false
  var path: String?
  var width: Int?
  var height: Int?
  var text: String?
  var qr: [String]?
}

/// Longest side of a kept photo, in pixels.
private let maxSide: CGFloat = 1600

class CameraPlugin: Plugin, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPickerViewControllerDelegate {
  private var pending: (invoke: Invoke, args: CaptureArgs)?

  @objc public func capture(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(CaptureArgs.self)
    if let folder = args.saveTo, !CameraPlugin.isInsideAppData(folder) { return invoke.reject("bad_folder") }
    guard pending == nil else { return invoke.reject("busy") }
    pending = (invoke, args)
    if args.source == "library" { return DispatchQueue.main.async { self.presentLibrary() } }
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return fail("no_camera") }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: DispatchQueue.main.async { self.presentCamera() }
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async { granted ? self.presentCamera() : self.fail("camera_denied") }
      }
    default: fail("camera_denied")
    }
  }

  private func fail(_ code: String) {
    pending?.invoke.reject(code)
    pending = nil
  }

  private func cancel() {
    pending?.invoke.resolve(CaptureResult(cancelled: true))
    pending = nil
  }

  private func presentCamera() {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = self
    manager.viewController?.present(picker, animated: true)
  }

  private func presentLibrary() {
    var config = PHPickerConfiguration()
    config.filter = .images
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    manager.viewController?.present(picker, animated: true)
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    cancel()
  }

  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    picker.dismiss(animated: true)
    guard let image = info[.originalImage] as? UIImage else { return cancel() }
    handle(image)
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return cancel() }
    provider.loadObject(ofClass: UIImage.self) { object, _ in
      guard let image = object as? UIImage else { return DispatchQueue.main.async { self.fail("bad_photo") } }
      self.handle(image)
    }
  }

  private func handle(_ image: UIImage) {
    guard let (invoke, args) = pending else { return }
    pending = nil
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        var result = CaptureResult()
        CameraPlugin.read(image, args.read, into: &result)
        if let folder = args.saveTo { try CameraPlugin.save(image, in: folder, into: &result) }
        invoke.resolve(result)
      } catch {
        let full = (error as NSError).code == NSFileWriteOutOfSpaceError
        invoke.reject(full ? "no_space" : "save_failed")
      }
    }
  }

  private static func read(_ image: UIImage, _ what: ReadArgs?, into result: inout CaptureResult) {
    guard let cg = image.cgImage else { return }
    var requests: [VNRequest] = []
    let textRequest = VNRecognizeTextRequest()
    textRequest.recognitionLevel = .accurate
    let qrRequest = VNDetectBarcodesRequest()
    qrRequest.symbologies = [.qr]
    if what?.text == true { requests.append(textRequest) }
    if what?.qr == true { requests.append(qrRequest) }
    guard !requests.isEmpty else { return }
    try? VNImageRequestHandler(cgImage: cg, orientation: visionOrientation(image.imageOrientation)).perform(requests)
    if what?.text == true {
      result.text = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    if what?.qr == true {
      result.qr = (qrRequest.results ?? []).compactMap { $0.payloadStringValue }
    }
  }

  /// A JPEG in `folder`, upright, in the app's protected storage and out of phone backups.
  private static func save(_ image: UIImage, in folder: String, into result: inout CaptureResult) throws {
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    guard let jpeg = upright.jpegData(compressionQuality: 0.85) else { throw CocoaError(.fileWriteUnknown) }
    let dir = URL(fileURLWithPath: folder, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var file = dir.appendingPathComponent("\(UUID().uuidString).jpg")
    try jpeg.write(to: file, options: [.atomic, .completeFileProtection])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try file.setResourceValues(values)
    result.path = file.path
    result.width = Int(size.width)
    result.height = Int(size.height)
  }

  private static func isInsideAppData(_ folder: String) -> Bool {
    let path = URL(fileURLWithPath: folder).standardizedFileURL.path
    let roots = [FileManager.SearchPathDirectory.applicationSupportDirectory, .documentDirectory].compactMap {
      FileManager.default.urls(for: $0, in: .userDomainMask).first?.standardizedFileURL.path
    }
    return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
  }

  private static func visionOrientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch o {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}

@_cdecl("init_plugin_camera")
func initPlugin() -> Plugin {
  return CameraPlugin()
}
