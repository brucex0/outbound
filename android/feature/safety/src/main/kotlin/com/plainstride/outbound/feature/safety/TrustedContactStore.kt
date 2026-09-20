package com.plainstride.outbound.feature.safety

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.core.network.apiCall

/**
 * Server-backed trusted contacts with a device-local cache so the list survives
 * delete/reinstall. The server row set is authoritative; the cache keeps the
 * last-known display names for offline rendering. Trusted contacts reference
 * in-app connections by user id — the contact book is never involved.
 */
@Singleton class DeviceTrustedContactStore @Inject constructor(
 @ApplicationContext context:Context,
 private val api:SafetyApi,
 private val tokens:AccessTokenProvider,
):TrustedContactStore{
 private val preferences=context.getSharedPreferences("trusted_contacts",Context.MODE_PRIVATE)
 private val lock=Mutex()
 override suspend fun contacts()=withContext(Dispatchers.IO){decode()}
 override suspend fun save(contact:TrustedContact)=withContext(Dispatchers.IO){
  val updated=decode().filterNot{it.id==contact.id}.toMutableList().apply{if(contact.isDefault)replaceAll{it.copy(isDefault=false)};add(contact)}
  preferences.edit().putString(KEY,PlainstrideJson.encodeToString(ListSerializer,updated)).commit();Unit
 }
 override suspend fun remove(id:String)=withContext(Dispatchers.IO){preferences.edit().putString(KEY,PlainstrideJson.encodeToString(ListSerializer,decode().filterNot{it.id==id})).commit();Unit}

 /**
  * One-time migration from the pre-server phone-book store: those rows held
  * device-local name/phone pairs with random ids, which can never match
  * connection user ids, so they are dropped before the first server pull.
  */
 override suspend fun migrateToServerBackedContacts()=withContext(Dispatchers.IO){
  if(preferences.getBoolean(MIGRATED,false))return@withContext
  preferences.edit().remove(KEY).putBoolean(MIGRATED,true).commit();Unit
 }

 /** Pull the server list into the cache, preserving last-known display names. */
 override suspend fun pull(accountId:String){lock.withLock{
  val remote=authenticated{apiCall{api.trustedContacts(it)}}.getOrNull()?:return@withLock
  val cached=decode().associateBy{it.id}
  val merged=remote.contactUserIds.map{id->
   val known=cached[id]
   TrustedContact(id,known?.displayName.orEmpty(),CHANNEL_PUSH,known?.address.orEmpty(),id==remote.defaultContactUserId)
  }
  withContext(Dispatchers.IO){preferences.edit().putString(KEY,PlainstrideJson.encodeToString(ListSerializer,merged)).commit()}
 }}

 /** Push the cached list to the server after a local mutation. */
 override suspend fun push(){lock.withLock{
  val current=decode()
  authenticated{apiCall{api.putTrustedContacts(it,PutTrustedContactsRequest(current.map{c->c.id},current.firstOrNull{c->c.isDefault}?.id))}}
 }}

 private suspend fun<T:Any>authenticated(call:suspend(String)->ApiResult<T>):Result<T>{val token=tokens.validAccessToken()?:return Result.failure(IllegalStateException("signed_out"));return when(val value=call("Bearer $token")){is ApiResult.Success->Result.success(value.value);is ApiResult.Failure->Result.failure(IllegalStateException(value.error.code.name))}}
 private fun decode()=preferences.getString(KEY,null)?.let{runCatching{PlainstrideJson.decodeFromString(ListSerializer,it)}.getOrNull()}.orEmpty()
 private companion object{const val KEY="contacts";const val MIGRATED="server_backed_migrated_v1";const val CHANNEL_PUSH="push";val ListSerializer=kotlinx.serialization.builtins.ListSerializer(TrustedContact.serializer())}
}

@Module @InstallIn(SingletonComponent::class) abstract class TrustedContactModule{
 @Binds @Singleton abstract fun bindTrustedContactStore(store:DeviceTrustedContactStore):TrustedContactStore
}
