package com.ahmadhussain.bletestperipheral

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

class MainActivity : ComponentActivity() {

    private val uiState = mutableStateOf(PeripheralState())
    private lateinit var server: PeripheralServer

    private val requiredPermissions: Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            emptyArray() // install-time BLUETOOTH / BLUETOOTH_ADMIN
        }

    private val permissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
            if (results.values.all { it }) server.start()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A test peripheral must not sleep in the middle of a test run.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        server = PeripheralServer(applicationContext) { uiState.value = it }
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    val state by uiState
                    PeripheralScreen(
                        state = state,
                        onStart = ::startWithPermissions,
                        onStop = server::stop,
                        onBond = server::bondCentrals,
                    )
                }
            }
        }
    }

    /**
     * `adb shell am start -n com.ahmadhussain.bletestperipheral/.MainActivity --ez bond true`
     * triggers the Bond button from the test computer (singleTop: same instance).
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra(EXTRA_BOND, false)) server.bondCentrals()
    }

    private fun startWithPermissions() {
        val missing = requiredPermissions.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) server.start() else permissionLauncher.launch(missing.toTypedArray())
    }

    override fun onDestroy() {
        server.stop()
        super.onDestroy()
    }

    private companion object {
        const val EXTRA_BOND = "bond"
    }
}

@Composable
private fun PeripheralScreen(
    state: PeripheralState,
    onStart: () -> Unit,
    onStop: () -> Unit,
    onBond: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text("BLE Test Peripheral", style = MaterialTheme.typography.titleLarge)
        Text("Server: ${if (state.running) "running" else "stopped"}")
        Text("Advertising: ${if (state.advertising) "on" else "off"}")
        Text("Connected centrals: ${state.centrals.ifEmpty { listOf("none") }.joinToString()}")
        Text("Subscribed: ${state.subscribers}")
        Text("Counter: ${state.counter}", style = MaterialTheme.typography.headlineMedium)
        Text("Last command: ${state.lastCommand}")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = onStart, enabled = !state.running) { Text("Start") }
            OutlinedButton(onClick = onStop, enabled = state.running) { Text("Stop") }
            OutlinedButton(onClick = onBond, enabled = state.centrals.isNotEmpty()) { Text("Bond") }
        }
        Spacer(Modifier.height(4.dp))
        Text("Log", style = MaterialTheme.typography.titleSmall)
        LazyColumn(reverseLayout = true, modifier = Modifier.weight(1f)) {
            items(state.log.asReversed()) { line ->
                Text(line, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
            }
        }
    }
}
