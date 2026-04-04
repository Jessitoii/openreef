package com.openreef.app.openreef.wake

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

// Hosts the nightly AutoDream background entry point.
//
// This worker is a no-op stub that reserves the WorkManager integration point
// for future memory consolidation without touching agent or memory logic yet.
class AutoDreamWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result = Result.success()

    companion object {
        const val UNIQUE_WORK_NAME = "openreef.auto_dream.nightly"
    }
}
