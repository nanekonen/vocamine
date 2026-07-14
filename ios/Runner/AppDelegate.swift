import Flutter
import UIKit
import VisionKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  VNDocumentCameraViewControllerDelegate
{
  private var scannerChannel: FlutterMethodChannel?
  private var pendingScanResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard
      let registrar = engineBridge.pluginRegistry.registrar(
        forPlugin: "GlossalyzeDocumentScanner")
    else { return }

    let channel = FlutterMethodChannel(
      name: "glossalyze/document_scanner",
      binaryMessenger: registrar.messenger())
    scannerChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "scanDocument" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.startDocumentScan(result: result)
    }
  }

  private func startDocumentScan(result: @escaping FlutterResult) {
    guard VNDocumentCameraViewController.isSupported else {
      result(
        FlutterError(
          code: "scanner_unavailable",
          message: "この端末では書類スキャンを利用できません",
          details: nil))
      return
    }
    guard pendingScanResult == nil else {
      result(
        FlutterError(
          code: "scan_in_progress",
          message: "書類スキャンを実行中です",
          details: nil))
      return
    }

    pendingScanResult = result
    let scanner = VNDocumentCameraViewController()
    scanner.delegate = self
    topViewController()?.present(scanner, animated: true)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFinishWith scan: VNDocumentCameraScan
  ) {
    var pages: [FlutterStandardTypedData] = []
    for index in 0..<scan.pageCount {
      if let data = scan.imageOfPage(at: index).jpegData(compressionQuality: 0.94) {
        pages.append(FlutterStandardTypedData(bytes: data))
      }
    }
    controller.dismiss(animated: true) { [weak self] in
      self?.finishScan(with: pages)
    }
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true) { [weak self] in
      self?.finishScan(with: [])
    }
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    controller.dismiss(animated: true) { [weak self] in
      guard let self else { return }
      let result = self.pendingScanResult
      self.pendingScanResult = nil
      result?(
        FlutterError(
          code: "scan_failed",
          message: error.localizedDescription,
          details: nil))
    }
  }

  private func finishScan(with pages: [FlutterStandardTypedData]) {
    let result = pendingScanResult
    pendingScanResult = nil
    result?(pages)
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }?
      .rootViewController
    var current = root
    while let presented = current?.presentedViewController {
      current = presented
    }
    return current
  }
}
