import Flutter
import Foundation

// MARK: - Gaze Stream Handler
class GazeStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: EyeTrackingPlugin?
    
    init(plugin: EyeTrackingPlugin) {
        self.plugin = plugin
        super.init()
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.setGazeEventSink(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.setGazeEventSink(nil)
        return nil
    }
}

// MARK: - Eye State Stream Handler
class EyeStateStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: EyeTrackingPlugin?
    
    init(plugin: EyeTrackingPlugin) {
        self.plugin = plugin
        super.init()
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.setEyeStateEventSink(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.setEyeStateEventSink(nil)
        return nil
    }
}

// MARK: - Head Pose Stream Handler
class HeadPoseStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: EyeTrackingPlugin?
    
    init(plugin: EyeTrackingPlugin) {
        self.plugin = plugin
        super.init()
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.setHeadPoseEventSink(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.setHeadPoseEventSink(nil)
        return nil
    }
}

// MARK: - Face Detection Stream Handler
class FaceDetectionStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: EyeTrackingPlugin?
    
    init(plugin: EyeTrackingPlugin) {
        self.plugin = plugin
        super.init()
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.setFaceDetectionEventSink(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.setFaceDetectionEventSink(nil)
        return nil
    }
}