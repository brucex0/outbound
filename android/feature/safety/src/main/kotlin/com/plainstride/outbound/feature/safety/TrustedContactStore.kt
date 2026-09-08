package com.plainstride.outbound.feature.safety

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import com.plainstride.outbound.core.network.PlainstrideJson

data class PickedContact(val displayName:String,val phoneNumber:String)

/** Device-local by design; release backup rules exclude this preference file and its PII. */
@Singleton class DeviceTrustedContactStore @Inject constructor(@ApplicationContext context:Context):TrustedContactStore{
 private val preferences=context.getSharedPreferences("trusted_contacts",Context.MODE_PRIVATE)
 override suspend fun contacts()=withContext(Dispatchers.IO){decode()}
 override suspend fun save(contact:TrustedContact)=withContext(Dispatchers.IO){
  val updated=decode().filterNot{it.id==contact.id}.toMutableList().apply{if(contact.isDefault)replaceAll{it.copy(isDefault=false)};add(contact)}
  preferences.edit().putString(KEY,PlainstrideJson.encodeToString(ListSerializer,updated)).commit();Unit
 }
 suspend fun savePicked(contact:PickedContact,makeDefault:Boolean=false)=save(TrustedContact(UUID.randomUUID().toString(),contact.displayName,"sms",contact.phoneNumber,makeDefault))
 override suspend fun remove(id:String)=withContext(Dispatchers.IO){preferences.edit().putString(KEY,PlainstrideJson.encodeToString(ListSerializer,decode().filterNot{it.id==id})).commit();Unit}
 private fun decode()=preferences.getString(KEY,null)?.let{runCatching{PlainstrideJson.decodeFromString(ListSerializer,it)}.getOrNull()}.orEmpty()
 private companion object{const val KEY="contacts";val ListSerializer=kotlinx.serialization.builtins.ListSerializer(TrustedContact.serializer())}
}

@Module @InstallIn(SingletonComponent::class) abstract class TrustedContactModule{
 @Binds @Singleton abstract fun bindTrustedContactStore(store:DeviceTrustedContactStore):TrustedContactStore
}
