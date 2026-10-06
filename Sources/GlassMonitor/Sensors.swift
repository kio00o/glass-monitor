import Foundation
import IOKit.ps
import CoreWLAN
import IOBluetooth
import CoreAudio

// MARK: - Private IOHID temperature API (same approach used by asitop / stats apps)

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(_ client: CFTypeRef, _ matching: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: CFTypeRef) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(_ service: CFTypeRef, _ type: Int64, _ options: Int32, _ timestamp: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(_ service: CFTypeRef, _ key: CFString) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: CFTypeRef, _ field: Int32) -> Double

enum Sensors {
    // MARK: Disk
    struct Disk { var available: Int64; var total: Int64 }

    static func disk() -> Disk {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        let v = try? url.resourceValues(forKeys: keys)
        return Disk(available: v?.volumeAvailableCapacityForImportantUsage ?? 0,
                    total: Int64(v?.volumeTotalCapacity ?? 0))
    }

    static func volumeName() -> String {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD"
    }

    // MARK: Memory pressure (%), 0 = plenty free, 100 = exhausted
    static func memoryPressure() -> Int {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 else { return 0 }
        return max(0, min(100, 100 - Int(level)))
    }

    // MARK: Battery
    struct Battery { var percent: Int; var charging: Bool; var minutes: Int?; var present: Bool }

    static func battery() -> Battery {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            var mins = d[key] as? Int
            if let m = mins, m < 0 { mins = nil }
            return Battery(percent: max > 0 ? cur * 100 / max : cur, charging: charging, minutes: mins, present: true)
        }
        return Battery(percent: 100, charging: false, minutes: nil, present: false)
    }

    // MARK: CPU load
    private static var prevTicks: [UInt32]?

    static func cpuLoad() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let t = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { prevTicks = t }
        guard let p = prevTicks else { return 0 }
        let d = zip(t, p).map { Double($0 &- $1) }
        let total = d.reduce(0, +)
        return total > 0 ? (total - d[2]) / total : 0
    }

    // MARK: CPU temperature (°C)
    static func cpuTemperature() -> Double? {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        let match: [String: Any] = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5]
        _ = IOHIDEventSystemClientSetMatching(client, match as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        var temps: [Double] = []
        for s in services {
            let name = IOHIDServiceClientCopyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
            guard name.contains("tdie") || name.contains("tcal") || name.contains("SOC") else { continue }
            if let ev = IOHIDServiceClientCopyEvent(s, 15, 0, 0)?.takeRetainedValue() {
                let v = IOHIDEventGetFloatValue(ev, 15 << 16)
                if v > 0 && v < 150 { temps.append(v) }
            }
        }
        return temps.max()
    }

    // MARK: Network throughput
    private static var prevNet: (rx: UInt64, tx: UInt64, t: TimeInterval)?
    private static var rxCarry: UInt64 = 0, txCarry: UInt64 = 0
    static var totalRx: UInt64 = 0, totalTx: UInt64 = 0

    /// Bytes per second (down, up) across physical interfaces.
    static func throughput() -> (down: Double, up: Double) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0) }
        defer { freeifaddrs(ifap) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let a = cur.pointee
            if let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               String(cString: a.ifa_name).hasPrefix("en"),
               (a.ifa_flags & UInt32(IFF_UP)) != 0, let data = a.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(d.ifi_ibytes); tx += UInt64(d.ifi_obytes)
            }
            p = a.ifa_next
        }
        totalRx = rx; totalTx = tx
        let now = Date.timeIntervalSinceReferenceDate
        defer { prevNet = (rx, tx, now) }
        guard let prev = prevNet, now > prev.t else { return (0, 0) }
        let dt = now - prev.t
        let dr = rx >= prev.rx ? rx - prev.rx : 0
        let dtx = tx >= prev.tx ? tx - prev.tx : 0
        return (Double(dr) / dt, Double(dtx) / dt)
    }

    // MARK: Wi-Fi
    static func ssid() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    static func security() -> String {
        switch CWWiFiClient.shared().interface()?.security() {
        case .wpa3Personal?, .wpa3Transition?: return "WPA3 Personal"
        case .wpa2Personal?: return "WPA2 Personal"
        case .wpaPersonal?, .wpaPersonalMixed?: return "WPA Personal"
        case .wpa2Enterprise?, .wpa3Enterprise?: return "Enterprise"
        case .some(.none): return "Open"
        default: return "Secured"
        }
    }

    static func linkRate() -> Int { Int(CWWiFiClient.shared().interface()?.transmitRate() ?? 0) }

    // MARK: Audio output
    /// True while any app is playing sound through the default output device.
    static func audioPlaying() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr,
              dev != 0 else { return false }
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    // MARK: Bluetooth
    struct Device: Identifiable, Hashable { var id: String; var name: String; var symbol: String }

    static func bluetoothDevices() -> [Device] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired.filter { $0.isConnected() }.map { d in
            let name = d.name ?? "Device"
            let l = name.lowercased()
            let symbol: String
            if l.contains("airpods max") { symbol = "airpodsmax" }
            else if l.contains("airpods pro") { symbol = "airpodspro" }
            else if l.contains("airpods") { symbol = "airpods" }
            else if l.contains("beats") { symbol = "beats.headphones" }
            else if l.contains("headphone") || l.contains("buds") || l.contains("headset") { symbol = "headphones" }
            else if l.contains("keyboard") || l.contains("vortex") { symbol = "keyboard" }
            else if l.contains("magic mouse") { symbol = "magicmouse" }
            else if l.contains("mouse") || l.contains("trackpad") || l.contains("orochi") { symbol = "computermouse" }
            else if l.contains("watch") { symbol = "applewatch" }
            else if l.contains("ipad") { symbol = "ipad" }
            else if l.contains("iphone") { symbol = "iphone" }
            else if l.contains("controller") || l.contains("dualsense") || l.contains("gamepad") || l.contains("xbox") { symbol = "gamecontroller" }
            else if l.contains("speaker") || l.contains("jbl") || l.contains("homepod") || l.contains("charge") { symbol = "hifispeaker" }
            else { symbol = "wave.3.right" }
            return Device(id: d.addressString ?? name, name: name, symbol: symbol)
        }
    }
}
