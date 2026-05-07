package com.example.eggplantdetector

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.example.eggplantdetector.databinding.ActivityHomeBinding
import com.google.android.material.dialog.MaterialAlertDialogBuilder

class HomeActivity : AppCompatActivity() {

    private lateinit var binding: ActivityHomeBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityHomeBinding.inflate(layoutInflater)
        setContentView(binding.root)

        ViewCompat.setOnApplyWindowInsetsListener(binding.homeBottomBar) { view, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.navigationBars())
            view.setPadding(view.paddingLeft, view.paddingTop, view.paddingRight, bars.bottom)
            insets
        }

        val active = ContextCompat.getColor(this, R.color.home_accent_green)
        val inactive = ContextCompat.getColor(this, R.color.home_nav_inactive)
        binding.navHome.setTextColor(active)
        binding.navLibrary.setTextColor(inactive)
        binding.navHistory.setTextColor(inactive)
        binding.navAbout.setTextColor(inactive)

        binding.startScanningButton.setOnClickListener {
            openScanner(CaptureMode.LIVE)
        }
        binding.uploadImageButton.setOnClickListener {
            openScanner(CaptureMode.PHOTO)
        }
        binding.homeFabScan.setOnClickListener {
            openScanner(CaptureMode.LIVE)
        }

        binding.navHome.setOnClickListener {
            binding.homeScroll.smoothScrollTo(0, 0)
        }
        binding.navLibrary.setOnClickListener { showComingSoon(getString(R.string.home_nav_library).substringAfter("\n")) }
        binding.navHistory.setOnClickListener { showComingSoon(getString(R.string.home_nav_history).substringAfter("\n")) }
        binding.navAbout.setOnClickListener { showComingSoon(getString(R.string.home_nav_about).substringAfter("\n")) }

        binding.tileDiseaseGuide.setOnClickListener { showComingSoon(getString(R.string.home_tile_disease_guide)) }
        binding.tileScanHistory.setOnClickListener { showComingSoon(getString(R.string.home_tile_scan_history)) }
        binding.tileHowToUse.setOnClickListener { showComingSoon(getString(R.string.home_tile_how_to_use)) }
        binding.tileAboutApp.setOnClickListener { showComingSoon(getString(R.string.home_tile_about_app)) }
    }

    private fun openScanner(mode: CaptureMode) {
        val intent = Intent(this, MainActivity::class.java).apply {
            putExtra(MainActivity.EXTRA_INITIAL_CAPTURE_MODE, mode.name)
        }
        startActivity(intent)
    }

    private fun showComingSoon(label: String) {
        MaterialAlertDialogBuilder(this)
            .setTitle(getString(R.string.home_coming_soon_title))
            .setMessage(getString(R.string.home_coming_soon_message, label))
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }
}
