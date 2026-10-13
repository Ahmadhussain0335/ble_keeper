package com.ahmadhussain.ble_keeper.gatt

import com.ahmadhussain.ble_keeper.PDisconnectReason

/**
 * Maps the `status` of BluetoothGattCallback.onConnectionStateChange to a
 * disconnect reason. Values below 0x80 are HCI error codes (Bluetooth Core
 * Spec Vol 1, Part F); 133 and 147 are Android stack codes.
 */
internal object GattStatus {
    const val SUCCESS = 0
    const val CONNECTION_TIMEOUT = 0x08
    const val REMOTE_USER_TERMINATED = 0x13
    const val LOCAL_HOST_TERMINATED = 0x16
    const val LMP_RESPONSE_TIMEOUT = 0x22
    const val FAILED_TO_ESTABLISH = 0x3E

    /** GATT_ERROR. Catch-all; on many stacks it means "connect failed, close and retry". */
    const val GATT_ERROR = 133

    /** BluetoothGatt.GATT_CONNECTION_TIMEOUT (API 35): direct connect timed out. */
    const val GATT_CONNECTION_TIMEOUT = 147

    /**
     * @param linkWasUp true when the connection had been established before
     * this callback (services discovered or at least connected).
     * @param localRequest true when the plugin called disconnect() itself.
     */
    fun disconnectReason(status: Int, linkWasUp: Boolean, localRequest: Boolean): PDisconnectReason =
        when {
            localRequest -> PDisconnectReason.LOCAL_TERMINATED
            status == REMOTE_USER_TERMINATED -> PDisconnectReason.PEER_TERMINATED
            status == CONNECTION_TIMEOUT || status == LMP_RESPONSE_TIMEOUT -> PDisconnectReason.LINK_LOSS
            status == LOCAL_HOST_TERMINATED -> PDisconnectReason.LOCAL_TERMINATED
            status == FAILED_TO_ESTABLISH || status == GATT_CONNECTION_TIMEOUT -> PDisconnectReason.CONNECT_FAILED
            status == GATT_ERROR && !linkWasUp -> PDisconnectReason.CONNECT_FAILED
            else -> PDisconnectReason.UNKNOWN
        }

    /** Failures that come back immediately and need backoff before retrying. */
    fun needsBackoff(status: Int, linkWasUp: Boolean): Boolean =
        !linkWasUp || status == GATT_ERROR
}
