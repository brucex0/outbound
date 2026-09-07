package run.plainstride.wear

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.WearableListenerService

class WearDataService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path == WearSessionGatewayImpl.STATE_PATH) WearSessionStateStore.accept(event.data)
    }
    override fun onDataChanged(events: DataEventBuffer) {
        events.forEach { event -> if (event.dataItem.uri.path == WearSessionGatewayImpl.STATE_PATH) com.google.android.gms.wearable.DataMapItem.fromDataItem(event.dataItem).dataMap.getString(WearSessionGatewayImpl.STATE_DATA_KEY)?.let(WearSessionStateStore::acceptJson) }
    }
}
