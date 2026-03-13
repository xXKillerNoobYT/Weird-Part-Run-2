fn main() {
    // Compile the ObjC Multipeer Connectivity bridge on macOS/iOS.
    // On other platforms (Windows, Linux), this block is skipped —
    // the Rust code uses cfg(target_os) to stub out Multipeer calls.
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        cc::Build::new()
            .file("objc/MultipeerBridge.m")
            .include("objc")
            .flag("-fobjc-arc") // Automatic Reference Counting
            .compile("multipeer_bridge");

        // Link Apple frameworks needed by MultipeerConnectivity
        println!("cargo:rustc-link-lib=framework=MultipeerConnectivity");
        println!("cargo:rustc-link-lib=framework=Foundation");

        // Re-run build if ObjC sources change
        println!("cargo:rerun-if-changed=objc/MultipeerBridge.m");
        println!("cargo:rerun-if-changed=objc/MultipeerBridge.h");
    }

    tauri_build::build()
}
