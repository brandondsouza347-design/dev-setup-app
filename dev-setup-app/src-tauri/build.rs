fn main() {
    println!("cargo:rerun-if-changed=../scripts/windows/admin_agent.ps1");

    #[cfg(target_os = "windows")]
    let attrs = tauri_build::Attributes::new().windows_attributes(
        tauri_build::WindowsAttributes::new()
            .app_manifest(include_str!("app.manifest")),
    );

    #[cfg(not(target_os = "windows"))]
    let attrs = tauri_build::Attributes::new();

    tauri_build::try_build(attrs).expect("failed to run tauri-build");
}
