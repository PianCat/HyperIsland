package com.example.hyperisland

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodCall

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.hyperisland/test"
    private val TAG = "HyperIsland"
    private val REQUEST_NOTIFICATION_PERMISSION = 1001

    private var pendingResult: MethodChannel.Result? = null
    private var pendingCall: MethodCall? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        checkAndRequestNotificationPermission()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "showProgress" -> {
                    if (checkNotificationPermission()) {
                        handleShowProgress(call, result)
                    } else {
                        pendingResult = result
                        pendingCall = call
                        requestNotificationPermission()
                    }
                }

                "showComplete" -> {
                    if (checkNotificationPermission()) {
                        handleShowComplete(call, result)
                    } else {
                        pendingResult = result
                        pendingCall = call
                        requestNotificationPermission()
                    }
                }

                "showFailed" -> {
                    if (checkNotificationPermission()) {
                        handleShowFailed(call, result)
                    } else {
                        pendingResult = result
                        pendingCall = call
                        requestNotificationPermission()
                    }
                }

                "showIndeterminate" -> {
                    if (checkNotificationPermission()) {
                        handleShowIndeterminate(call, result)
                    } else {
                        pendingResult = result
                        pendingCall = call
                        requestNotificationPermission()
                    }
                }

                "showCustom" -> {
                    if (checkNotificationPermission()) {
                        handleShowCustom(call, result)
                    } else {
                        pendingResult = result
                        pendingCall = call
                        requestNotificationPermission()
                    }
                }

                "isModuleActive" -> {
                    result.success(isModuleActive())
                }

                "checkPermission" -> {
                    result.success(checkNotificationPermission())
                }

                "requestPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    // 默认返回 false；LSPosed Hook 加载后会将此方法替换为返回 true
    fun isModuleActive(): Boolean = false

    private fun checkNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun checkAndRequestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQUEST_NOTIFICATION_PERMISSION
                )
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATION_PERMISSION
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED

            if (granted && pendingCall != null && pendingResult != null) {
                // 重新执行被挂起的调用
                when (pendingCall!!.method) {
                    "showProgress" -> handleShowProgress(pendingCall!!, pendingResult!!)
                    "showComplete" -> handleShowComplete(pendingCall!!, pendingResult!!)
                    "showFailed" -> handleShowFailed(pendingCall!!, pendingResult!!)
                    "showIndeterminate" -> handleShowIndeterminate(pendingCall!!, pendingResult!!)
                    "showCustom" -> handleShowCustom(pendingCall!!, pendingResult!!)
                }
                pendingResult = null
                pendingCall = null
            } else if (!granted) {
                pendingResult?.success(false)
                pendingResult = null
                pendingCall = null
                Log.w(TAG, "Notification permission denied")
            }
        }
    }

    private fun handleShowProgress(call: MethodCall, result: MethodChannel.Result) {
        try {
            val title = call.argument<String>("title") ?: "下载中"
            val fileName = call.argument<String>("fileName") ?: ""
            val progress = call.argument<Int>("progress") ?: 0
            val speed = call.argument<String>("speed") ?: ""
            val remainingTime = call.argument<String>("remainingTime") ?: ""

            val success = HyperIslandHelper.showDownloadProgress(
                this,
                title,
                fileName,
                progress,
                speed,
                remainingTime
            )
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing progress", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleShowComplete(call: MethodCall, result: MethodChannel.Result) {
        try {
            val title = call.argument<String>("title") ?: "下载完成"
            val fileName = call.argument<String>("fileName") ?: ""

            val success = HyperIslandHelper.showDownloadComplete(
                this,
                title,
                fileName
            )
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing complete", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleShowFailed(call: MethodCall, result: MethodChannel.Result) {
        try {
            val title = call.argument<String>("title") ?: "下载失败"
            val fileName = call.argument<String>("fileName") ?: ""
            val error = call.argument<String>("error") ?: ""

            val success = HyperIslandHelper.showDownloadFailed(
                this,
                title,
                fileName,
                error
            )
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing failed", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleShowIndeterminate(call: MethodCall, result: MethodChannel.Result) {
        try {
            val title = call.argument<String>("title") ?: ""
            val content = call.argument<String>("content") ?: ""

            val success = HyperIslandHelper.showIndeterminateProgress(
                this,
                title,
                content
            )
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing indeterminate", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun handleShowCustom(call: MethodCall, result: MethodChannel.Result) {
        try {
            val type = call.argument<String>("type") ?: "custom"
            val title = call.argument<String>("title") ?: ""
            val content = call.argument<String>("content") ?: ""
            val icon = call.argument<String>("icon")

            val success = HyperIslandHelper.showCustomFocus(
                this,
                type,
                title,
                content,
                icon
            )
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing custom", e)
            result.error("ERROR", e.message, null)
        }
    }
}
