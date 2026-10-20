package com.jackwallner.time

import android.app.Application

class ShoesOnApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppGraph.get(this).diagnostics.recordAppOpen()
    }
}
