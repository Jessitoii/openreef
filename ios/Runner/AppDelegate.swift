import Flutter
import UIKit
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "openreef/device_stats",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "getDeviceStats" else {
          result(FlutterMethodNotImplemented)
          return
        }
        result(self?.fetchDeviceStats())
      }
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func fetchDeviceStats() -> [String: Any]? {
    let hostPort: mach_port_t = mach_host_self()
    var pageSize: vm_size_t = 0
    guard host_page_size(hostPort, &pageSize) == KERN_SUCCESS else {
      return nil
    }

    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout.size(ofValue: stats) / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &stats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
        host_statistics64(hostPort, HOST_VM_INFO64, pointer, &count)
      }
    }
    guard result == KERN_SUCCESS else {
      return nil
    }

    let freePages = Double(stats.free_count + stats.inactive_count)
    let freeBytes = freePages * Double(pageSize)
    let freeRamGb = freeBytes / (1024.0 * 1024.0 * 1024.0)
    return [
      "freeRamGb": freeRamGb,
      "npuReady": false
    ]
  }
}
