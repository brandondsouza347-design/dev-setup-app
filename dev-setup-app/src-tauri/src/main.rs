// main.rs — Entry point for the Tauri application
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod orchestrator;
mod state;

use state::AppState;
use std::sync::Mutex;

fn main() {
    tauri::Builder::default()
        .plugin(
            tauri_plugin_log::Builder::new()
                .level(log::LevelFilter::Info)
                .build(),
        )
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init())
        .manage(Mutex::new(AppState::default()))
        .invoke_handler(tauri::generate_handler![
            commands::detect_os,
            commands::get_setup_steps,
            commands::start_setup,
            commands::resume_setup,
            commands::run_step,
            commands::retry_step,
            commands::revert_setup_step,
            commands::skip_step,
            commands::get_state,
            commands::reset_state,
            commands::check_prerequisites,
            commands::open_terminal,
            commands::get_config,
            commands::save_config,
            commands::get_revert_steps,
            commands::start_revert,
        ])
        .setup(|_app| {
            log::info!(
                "dev-setup-app starting — OS={} ARCH={}",
                std::env::consts::OS,
                std::env::consts::ARCH
            );
            #[cfg(debug_assertions)]
            {
                use tauri::Manager;
                let window = _app.get_webview_window("main").unwrap();
                window.open_devtools();
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
