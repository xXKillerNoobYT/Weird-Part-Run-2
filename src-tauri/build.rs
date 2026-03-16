use std::process::Command;

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

        // ── Foundation Models Bridge (Swift) ──────────────────────────
        // Compile the Swift Foundation Models bridge.
        // Uses swiftc to produce a static library that Rust links against.
        // The Swift file uses @_cdecl to expose C-compatible symbols.
        compile_swift_bridge();
    }

    tauri_build::build()
}

/// Compile the Swift Foundation Models bridge into a static library.
///
/// We use `swiftc` directly because the `cc` crate doesn't support Swift files.
/// This produces `libfoundation_models_bridge.a` in the OUT_DIR.
#[cfg(any(target_os = "macos", target_os = "ios"))]
fn compile_swift_bridge() {
    let out_dir = std::env::var("OUT_DIR").expect("OUT_DIR not set");
    let swift_file = "swift/FoundationModelsBridge.swift";

    // Determine the target triple for cross-compilation
    let target = std::env::var("TARGET").unwrap_or_default();

    let mut cmd = Command::new("swiftc");

    cmd.arg(swift_file)
        .arg("-parse-as-library") // Don't look for @main
        .arg("-static")
        .arg("-emit-library")
        .arg("-module-name")
        .arg("FoundationModelsBridge")
        .arg("-o")
        .arg(format!("{out_dir}/libfoundation_models_bridge.a"));

    // Set the correct target for iOS vs macOS.
    // We query the deployment target from the environment (set by Xcode)
    // or fall back to the SDK version so swiftc can find its standard library.
    if target.contains("ios") {
        let ios_version = std::env::var("IPHONEOS_DEPLOYMENT_TARGET")
            .unwrap_or_else(|_| get_ios_sdk_version().unwrap_or_else(|| "17.0".to_string()));
        if target.contains("sim") {
            cmd.arg("-target")
                .arg(format!("arm64-apple-ios{ios_version}-simulator"));
            cmd.arg("-sdk").arg(get_sdk_path("iphonesimulator"));
        } else {
            cmd.arg("-target")
                .arg(format!("arm64-apple-ios{ios_version}"));
            cmd.arg("-sdk").arg(get_sdk_path("iphoneos"));
        }
    } else if target.contains("aarch64-apple-darwin") || target.contains("x86_64-apple-darwin") {
        cmd.arg("-target").arg(format!("{target}"));
    }

    // Suppress warnings, allow library evolution
    cmd.arg("-suppress-warnings");

    let output = cmd.output().expect("Failed to execute swiftc — is Xcode installed?");

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        // If the failure is because FoundationModels isn't available (older SDK),
        // we still succeed — the Rust code handles unavailability at runtime.
        if stderr.contains("No such module 'FoundationModels'") {
            eprintln!(
                "cargo:warning=FoundationModels framework not available in this SDK. \
                 The LLM bridge will compile with stubs only."
            );
            // Create an empty static library so linking doesn't fail
            Command::new("ar")
                .args(["rcs", &format!("{out_dir}/libfoundation_models_bridge.a")])
                .status()
                .ok();
        } else {
            panic!(
                "Swift compilation failed:\n{}\n{}",
                String::from_utf8_lossy(&output.stdout),
                stderr
            );
        }
    }

    // Tell Rust to link our Swift static library
    println!("cargo:rustc-link-search=native={out_dir}");
    println!("cargo:rustc-link-lib=static=foundation_models_bridge");

    // Link the Swift standard library and runtime
    // swiftc needs the Swift runtime libraries to be linked
    let swift_lib_dir = get_swift_lib_dir(&target);
    if let Some(dir) = swift_lib_dir {
        println!("cargo:rustc-link-search=native={dir}");
    }

    // Weak-link FoundationModels so the app runs on older OS versions
    // (the Swift code uses #available checks)
    println!("cargo:rustc-link-lib=framework=Foundation");

    // Re-run if Swift source changes
    println!("cargo:rerun-if-changed=swift/FoundationModelsBridge.swift");
}

/// Query the iOS SDK version via xcrun (e.g. "26.2", "17.0").
#[cfg(any(target_os = "macos", target_os = "ios"))]
fn get_ios_sdk_version() -> Option<String> {
    let output = Command::new("xcrun")
        .args(["--sdk", "iphonesimulator", "--show-sdk-version"])
        .output()
        .ok()?;
    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    }
}

/// Get the SDK path for a given platform name (e.g. "iphonesimulator", "iphoneos").
#[cfg(any(target_os = "macos", target_os = "ios"))]
fn get_sdk_path(sdk_name: &str) -> String {
    let output = Command::new("xcrun")
        .args(["--sdk", sdk_name, "--show-sdk-path"])
        .output()
        .expect("Failed to run xcrun --show-sdk-path");
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

/// Find the Swift standard library directory for the current platform.
#[cfg(any(target_os = "macos", target_os = "ios"))]
fn get_swift_lib_dir(target: &str) -> Option<String> {
    // Ask xcrun for the toolchain path
    let output = Command::new("xcrun")
        .args(["--show-sdk-path"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    let sdk_path = String::from_utf8_lossy(&output.stdout).trim().to_string();

    // The Swift compatibility libraries are in the SDK's usr/lib/swift directory
    let platform = if target.contains("ios-sim") || target.contains("simulator") {
        "iphonesimulator"
    } else if target.contains("ios") {
        "iphoneos"
    } else {
        "macosx"
    };

    // Try the toolchain's lib/swift/{platform} directory
    let toolchain_output = Command::new("xcrun")
        .args(["--toolchain", "default", "--find", "swiftc"])
        .output()
        .ok()?;

    if toolchain_output.status.success() {
        let swiftc_path = String::from_utf8_lossy(&toolchain_output.stdout)
            .trim()
            .to_string();
        // Go up from bin/swiftc to lib/swift/{platform}
        if let Some(bin_dir) = std::path::Path::new(&swiftc_path).parent() {
            if let Some(toolchain_dir) = bin_dir.parent() {
                let swift_lib = toolchain_dir
                    .join("lib")
                    .join("swift")
                    .join(platform);
                if swift_lib.exists() {
                    return Some(swift_lib.to_string_lossy().to_string());
                }
            }
        }
    }

    // Fallback: SDK path
    let swift_lib = format!("{sdk_path}/usr/lib/swift");
    if std::path::Path::new(&swift_lib).exists() {
        return Some(swift_lib);
    }

    None
}
