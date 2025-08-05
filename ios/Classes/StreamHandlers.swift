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
        print("🔔 GazeStreamHandler: Setting up gaze event stream")
        plugin?.setGazeEventSink(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("🔔 GazeStreamHandler: onCancel called")
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
        print("🔔 EyeStateStreamHandler: onListen called - setting up eye state event sink")
        plugin?.setEyeStateEventSink(events)
        print("✅ EyeStateStreamHandler: event sink configured")
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("🔔 EyeStateStreamHandler: onCancel called")
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
        print("🔔 HeadPoseStreamHandler: onListen called - setting up head pose event sink")
        plugin?.setHeadPoseEventSink(events)
        print("✅ HeadPoseStreamHandler: event sink configured")
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("🔔 HeadPoseStreamHandler: onCancel called")
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
        print("🔔 FaceDetectionStreamHandler: onListen called - setting up face detection event sink")
        plugin?.setFaceDetectionEventSink(events)
        print("✅ FaceDetectionStreamHandler: event sink configured")
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("🔔 FaceDetectionStreamHandler: onCancel called")
        plugin?.setFaceDetectionEventSink(nil)
        return nil
    }
}