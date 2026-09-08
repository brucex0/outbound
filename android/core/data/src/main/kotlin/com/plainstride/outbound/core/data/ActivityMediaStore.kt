package com.plainstride.outbound.core.data

import android.content.Context
import java.io.File
import java.util.UUID

/** Keeps activity media in app-private storage and exposes only relative references to Room. */
class ActivityMediaStore(context: Context) {
    private val root = File(context.filesDir, "activities").also { it.mkdirs() }

    fun write(accountId: String, activityId: String, bytes: ByteArray, extension: String = "jpg"): String {
        require(bytes.isNotEmpty()) { "Activity media cannot be empty." }
        val safeExtension = extension.lowercase().filter(Char::isLetterOrDigit).take(8).ifEmpty { "bin" }
        val directory = activityDirectory(accountId, activityId).also { it.mkdirs() }
        val target = File(directory, "photo-${UUID.randomUUID()}.$safeExtension")
        val temporary = File(directory, ".${target.name}.tmp")
        temporary.writeBytes(bytes)
        check(temporary.renameTo(target)) { "Unable to atomically persist activity media." }
        return target.relativeTo(root).invariantSeparatorsPath
    }

    fun read(relativePath: String): ByteArray = resolve(relativePath).readBytes()

    fun delete(relativePath: String): Boolean = resolve(relativePath).delete()

    fun deleteActivity(accountId: String, activityId: String): Boolean =
        activityDirectory(accountId, activityId).deleteRecursively()

    private fun activityDirectory(accountId: String, activityId: String) =
        File(File(root, safeSegment(accountId)), safeSegment(activityId))

    private fun resolve(relativePath: String): File {
        val candidate = File(root, relativePath).canonicalFile
        require(candidate.path.startsWith(root.canonicalPath + File.separator)) { "Invalid private media path." }
        return candidate
    }

    private fun safeSegment(value: String): String = value.filter { it.isLetterOrDigit() || it == '-' || it == '_' }.also {
        require(it.isNotEmpty()) { "Invalid activity media identifier." }
    }
}
