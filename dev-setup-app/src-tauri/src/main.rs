// main.rs — Entry point for the Tauri application
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod admin_agent;
mod commands;
mod orchestrator;
mod security;
mod state;

use state::{AppState, CancelState};
use std::sync::Mutex;
use tauri::Manager;

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
        .manage(CancelState::new())
        .manage(admin_agent::AdminAgentState::new())
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
            commands::install_openvpn_prereq,
            commands::connect_vpn_prereq,
            commands::open_terminal,
            commands::get_config,
            commands::save_config,
            commands::get_revert_steps,
            commands::start_revert,
            commands::request_admin_agent,
            commands::is_admin_agent_ready,
            commands::shutdown_admin_agent,
            commands::open_url,
            commands::restart_system,
            commands::stop_setup,
            commands::save_run_history,
            commands::load_run_history,
            commands::clear_run_history_by_ids,
            commands::save_config_profile,
            commands::list_config_profiles,
            commands::load_config_profile,
            commands::delete_config_profile,
            commands::save_workflow,
            commands::list_workflows,
            commands::delete_workflow,
            commands::update_workflow_last_run,
            commands::execute_workflow,
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
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { .. } = event {
                log::info!("Window close requested - cleaning up resources...");
                
                // Cancel any running operations
                if let Some(cancel_state) = window.app_handle().try_state::<CancelState>() {
                    cancel_state.cancel();
                    log::info!("Cancelled running operations");
                }
                
                // Shutdown admin agent if running
                if let Some(agent_state) = window.app_handle().try_state::<admin_agent::AdminAgentState>() {
                    if agent_state.is_ready() {
                        log::info!("Shutting down admin agent...");
                        let runtime = tokio::runtime::Runtime::new().unwrap();
                        runtime.block_on(async {
                            admin_agent::shutdown_agent(&agent_state).await;
                        });
                        log::info!("Admin agent shutdown complete");
                    }
                }
                
                log::info!("Cleanup complete - allowing window to close");
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
