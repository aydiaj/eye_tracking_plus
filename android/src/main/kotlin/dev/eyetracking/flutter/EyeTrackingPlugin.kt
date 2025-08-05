package dev.eyetracking.flutter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/** EyeTrackingPlugin */
class EyeTrackingPlugin: FlutterPlugin, MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
  /// The MethodChannel that will the communication between Flutter and native Android
  private lateinit var channel : MethodChannel
  private lateinit var context: Context
  private var activity: Activity? = null
  
  // Event channels for streaming data
  private lateinit var gazeEventChannel: EventChannel
  private lateinit var eyeStateEventChannel: EventChannel
  private lateinit var headPoseEventChannel: EventChannel
  private lateinit var faceDetectionEventChannel: EventChannel
  
  // Event sinks for streaming
  private var gazeEventSink: EventChannel.EventSink? = null
  private var eyeStateEventSink: EventChannel.EventSink? = null
  private var headPoseEventSink: EventChannel.EventSink? = null
  private var faceDetectionEventSink: EventChannel.EventSink? = null
  
  // Plugin state
  private var eyeTrackingState = "uninitialized"
  private var isInitialized = false
  private var isTracking = false
  private var isCalibrating = false
  
  companion object {
    const val CAMERA_PERMISSION_REQUEST_CODE = 100
  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "eye_tracking")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
    
    // Setup event channels for streaming data
    gazeEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "eye_tracking/gaze")
    eyeStateEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "eye_tracking/eye_state")
    headPoseEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "eye_tracking/head_pose")
    faceDetectionEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "eye_tracking/face_detection")
    
    setupEventChannels()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getPlatformVersion" -> {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      }
      "initialize" -> {
        initialize(result)
      }
      "requestCameraPermission" -> {
        requestCameraPermission(result)
      }
      "hasCameraPermission" -> {
        result.success(hasCameraPermission())
      }
      "getState" -> {
        result.success(eyeTrackingState)
      }
      "startTracking" -> {
        startTracking(result)
      }
      "stopTracking" -> {
        stopTracking(result)
      }
      "pauseTracking" -> {
        pauseTracking(result)
      }
      "resumeTracking" -> {
        resumeTracking(result)
      }
      "startCalibration" -> {
        val points = call.argument<List<Map<String, Any>>>("points")
        startCalibration(points, result)
      }
      "addCalibrationPoint" -> {
        val point = call.argument<Map<String, Any>>("point")
        addCalibrationPoint(point, result)
      }
      "finishCalibration" -> {
        finishCalibration(result)
      }
      "clearCalibration" -> {
        clearCalibration(result)
      }
      "getCalibrationAccuracy" -> {
        getCalibrationAccuracy(result)
      }
      "setTrackingFrequency" -> {
        val fps = call.argument<Int>("fps")
        setTrackingFrequency(fps, result)
      }
      "setAccuracyMode" -> {
        val mode = call.argument<String>("mode")
        setAccuracyMode(mode, result)
      }
      "enableBackgroundTracking" -> {
        val enable = call.argument<Boolean>("enable")
        enableBackgroundTracking(enable, result)
      }
      "getCapabilities" -> {
        getCapabilities(result)
      }
      "dispose" -> {
        dispose(result)
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  private fun setupEventChannels() {
    gazeEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        gazeEventSink = events
      }
      override fun onCancel(arguments: Any?) {
        gazeEventSink = null
      }
    })
    
    eyeStateEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eyeStateEventSink = events
      }
      override fun onCancel(arguments: Any?) {
        eyeStateEventSink = null
      }
    })
    
    headPoseEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        headPoseEventSink = events
      }
      override fun onCancel(arguments: Any?) {
        headPoseEventSink = null
      }
    })
    
    faceDetectionEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        faceDetectionEventSink = events
      }
      override fun onCancel(arguments: Any?) {
        faceDetectionEventSink = null
      }
    })
  }

  private fun initialize(result: Result) {
    if (isInitialized) {
      result.success(true)
      return
    }
    
    try {
      eyeTrackingState = "initializing"
      // Add your eye tracking initialization logic here
      // For now, just mark as ready
      eyeTrackingState = "ready"
      isInitialized = true
      result.success(true)
    } catch (e: Exception) {
      eyeTrackingState = "error"
      result.success(false)
    }
  }

  private fun requestCameraPermission(result: Result) {
    if (activity == null) {
      result.success(false)
      return
    }
    
    if (hasCameraPermission()) {
      result.success(true)
      return
    }
    
    ActivityCompat.requestPermissions(
      activity!!,
      arrayOf(Manifest.permission.CAMERA),
      CAMERA_PERMISSION_REQUEST_CODE
    )
    
    // Note: The actual result will be handled in onRequestPermissionsResult
    // For now, we'll return the current permission status
    result.success(hasCameraPermission())
  }

  private fun hasCameraPermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      context,
      Manifest.permission.CAMERA
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun startTracking(result: Result) {
    if (!isInitialized) {
      result.success(false)
      return
    }
    
    if (!hasCameraPermission()) {
      result.success(false)
      return
    }
    
    try {
      // Add your eye tracking start logic here
      eyeTrackingState = "tracking"
      isTracking = true
      result.success(true)
    } catch (e: Exception) {
      eyeTrackingState = "error"
      result.success(false)
    }
  }

  private fun stopTracking(result: Result) {
    try {
      // Add your eye tracking stop logic here
      eyeTrackingState = "ready"
      isTracking = false
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun pauseTracking(result: Result) {
    if (!isTracking) {
      result.success(false)
      return
    }
    
    try {
      // Add your eye tracking pause logic here
      eyeTrackingState = "paused"
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun resumeTracking(result: Result) {
    if (eyeTrackingState != "paused") {
      result.success(false)
      return
    }
    
    try {
      // Add your eye tracking resume logic here
      eyeTrackingState = "tracking"
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun startCalibration(points: List<Map<String, Any>>?, result: Result) {
    if (!isInitialized) {
      result.success(false)
      return
    }
    
    try {
      // Add your calibration start logic here
      eyeTrackingState = "calibrating"
      isCalibrating = true
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun addCalibrationPoint(point: Map<String, Any>?, result: Result) {
    if (!isCalibrating) {
      result.success(false)
      return
    }
    
    try {
      // Add your calibration point logic here
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun finishCalibration(result: Result) {
    if (!isCalibrating) {
      result.success(false)
      return
    }
    
    try {
      // Add your calibration finish logic here
      eyeTrackingState = "ready"
      isCalibrating = false
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun clearCalibration(result: Result) {
    try {
      // Add your calibration clear logic here
      if (isCalibrating) {
        eyeTrackingState = "ready"
        isCalibrating = false
      }
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun getCalibrationAccuracy(result: Result) {
    try {
      // Add your calibration accuracy logic here
      // For now, return a dummy value
      result.success(0.85) // 85% accuracy
    } catch (e: Exception) {
      result.success(0.0)
    }
  }

  private fun setTrackingFrequency(fps: Int?, result: Result) {
    try {
      // Add your tracking frequency logic here
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun setAccuracyMode(mode: String?, result: Result) {
    try {
      // Add your accuracy mode logic here
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun enableBackgroundTracking(enable: Boolean?, result: Result) {
    try {
      // Add your background tracking logic here
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  private fun getCapabilities(result: Result) {
    val capabilities = mapOf(
      "hasCamera" to true,
      "hasFrontCamera" to true,
      "supportsEyeTracking" to true,
      "supportsHeadPose" to true,
      "supportsFaceDetection" to true,
      "supportsCalibration" to true,
      "maxTrackingFrequency" to 60,
      "platform" to "android"
    )
    result.success(capabilities)
  }

  private fun dispose(result: Result) {
    try {
      // Clean up resources
      stopTracking(Result { /* ignore */ })
      isInitialized = false
      eyeTrackingState = "uninitialized"
      result.success(true)
    } catch (e: Exception) {
      result.success(false)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    when (requestCode) {
      CAMERA_PERMISSION_REQUEST_CODE -> {
        // Handle camera permission result
        return true
      }
    }
    return false
  }
}