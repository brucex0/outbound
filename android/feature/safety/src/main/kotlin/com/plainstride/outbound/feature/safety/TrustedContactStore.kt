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
 private val preferences=context.getSharedPreferences("server_trusted_contacts",Context.MODE_PRIVATE)
 private val lock=Mutex()
 override suspend fun contacts(accountId:String)=withContext(Dispatchers.IO){decode(accountId)}
 override suspend fun save(accountId:String,contact:TrustedContact)=withContext(Dispatchers.IO){
  val updated=decode(accountId).filterNot{it.id==contact.id}.toMutableList().apply{if(contact.isDefault)replaceAll{it.copy(isDefault=false)};add(contact)}
  preferences.edit().putString(contactsKey(accountId),PlainstrideJson.encodeToString(ListSerializer,updated)).commit();Unit
 }
 override suspend fun remove(accountId:String,id:String)=withContext(Dispatchers.IO){preferences.edit().putString(contactsKey(accountId),PlainstrideJson.encodeToString(ListSerializer,decode(accountId).filterNot{it.id==id})).commit();Unit}
 override suspend fun sharesWithTrustedContactsByDefault(accountId:String)=withContext(Dispatchers.IO){preferences.getBoolean(defaultShareKey(accountId),false)}
 override suspend fun setSharesWithTrustedContactsByDefault(accountId:String,enabled:Boolean)=withContext(Dispatchers.IO){preferences.edit().putBoolean(defaultShareKey(accountId),enabled).commit();Unit}

 /** Pull the server list into the cache, preserving last-known display names. */
 override suspend fun pull(accountId:String){lock.withLock{
  val remote=authenticated(accountId){apiCall{api.trustedContacts(it)}}.getOrNull()?:return@withLock
  val cached=decode(accountId).associateBy{it.id}
  val merged=remote.contactUserIds.map{id->
   val known=cached[id]
   TrustedContact(id,known?.displayName.orEmpty(),id==remote.defaultContactUserId)
  }
  withContext(Dispatchers.IO){preferences.edit().putString(contactsKey(accountId),PlainstrideJson.encodeToString(ListSerializer,merged)).commit()}
 }}

 /** Push the cached list to the server after a local mutation. */
 override suspend fun push(accountId:String){lock.withLock{
  val current=decode(accountId)
  authenticated(accountId){apiCall{api.putTrustedContacts(it,PutTrustedContactsRequest(current.map{c->c.id},current.firstOrNull{c->c.isDefault}?.id))}}
 }}

 private suspend fun<T:Any>authenticated(accountId:String,call:suspend(String)->ApiResult<T>):Result<T>{
  val requestContext=tokens.captureAccount(accountId)?:return Result.failure(IllegalStateException("signed_out"))
  val token=tokens.validAccessToken(requestContext)?:return Result.failure(IllegalStateException("signed_out"))
  val value=call("Bearer $token")
  if(!tokens.isCurrent(requestContext))throw kotlinx.coroutines.CancellationException("trusted_contacts_account_changed")
  return when(value){is ApiResult.Success->Result.success(value.value);is ApiResult.Failure->{
   android.util.Log.w("PlainstrideSafety","trusted_contacts_request failed category=${value.error.code} status=${value.error.httpStatus}")
   Result.failure(IllegalStateException(value.error.code.name))
  }}
 }
 private fun decode(accountId:String)=preferences.getString(contactsKey(accountId),null)?.let{runCatching{PlainstrideJson.decodeFromString(ListSerializer,it)}.getOrNull()}.orEmpty()
 private fun contactsKey(accountId:String)="contacts_$accountId"
 private fun defaultShareKey(accountId:String)="default_share_$accountId"
 private companion object{val ListSerializer=kotlinx.serialization.builtins.ListSerializer(TrustedContact.serializer())}
}

@Module @InstallIn(SingletonComponent::class) abstract class TrustedContactModule{
 @Binds @Singleton abstract fun bindTrustedContactStore(store:DeviceTrustedContactStore):TrustedContactStore
}
