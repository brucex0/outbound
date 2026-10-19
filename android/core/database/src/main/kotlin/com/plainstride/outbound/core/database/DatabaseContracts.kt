package com.plainstride.outbound.core.database

interface TransactionRunner {
    suspend fun <T> inTransaction(block: suspend () -> T): T
}
