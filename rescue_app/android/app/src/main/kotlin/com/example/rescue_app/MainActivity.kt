package com.example.rescue_app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Routes this app's traffic over Wi-Fi even when that Wi-Fi has no internet.
 *
 * Why this exists (bench finding 2026-07-14): a rescue drone's AP is
 * deliberately offline, so Android refuses to promote it to the default
 * network. With mobile data enabled, every request then leaves over
 * cellular, where 10.42.0.1 has no route, and the app fails with a bare
 * socket error even though the phone is sitting on RESCUE_A. Binding the
 * process to the Wi-Fi network fixes that without telling users to disable
 * mobile data (a victim in a disaster will not know to do that, and a
 * rescuer should not have to).
 *
 * Binding is safe here because this app only ever talks to the node.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "rescue_mesh/network"
    private var callback: ConnectivityManager.NetworkCallback? = null

    private val connectivity: ConnectivityManager
        get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "bindToWifi" -> {
                        bindToWifi()
                        result.success(true)
                    }
                    "unbind" -> {
                        unbind()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun bindToWifi() {
        unbind()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            // Do NOT require INTERNET: the drone AP has none, by design.
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                connectivity.bindProcessToNetwork(network)
            }

            override fun onLost(network: Network) {
                connectivity.bindProcessToNetwork(null)
            }
        }
        callback = cb
        try {
            connectivity.requestNetwork(request, cb)
        } catch (e: SecurityException) {
            // CHANGE_NETWORK_STATE missing: fall back to default routing.
            callback = null
        }
    }

    private fun unbind() {
        callback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (_: IllegalArgumentException) {
                // already unregistered
            }
        }
        callback = null
        connectivity.bindProcessToNetwork(null)
    }

    override fun onDestroy() {
        unbind()
        super.onDestroy()
    }
}
