// main.rs — Entry point for the Tauri application
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod orchestrator;
mod state;

use state::AppState;
use std::sync::Mutex;
use tauri::Manager;

fn main() {
    tauri::Builder::default()
        .manage(Mutex::new(AppState::default()))
        .invoke_handler(tauri::generate_handler![
            commands::detect_os,
            commands::get_setup_steps,
            commands::start_setup,
            commands::run_step,
            commands::retry_step,
            commands::skip_step,
            commands::get_state,
            commands::reset_state,
            commands::check_prerequisites,
            commands::open_terminal,
            commands::get_config,
            commands::save_config,
        ])
        .setup(|app| {
            let _window = app.get_window("main").unwrap();
            // Enable devtools in debug builds
            #[cfg(debug_assertions)]
            window.open_devtools();
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
