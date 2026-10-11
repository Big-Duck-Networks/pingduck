//! The agent as the Windows service `PingDuckAgent` (LocalSystem, starts with
//! Windows, restarts on failure). The installer runs `pingduck-agent install`
//! and `pingduck-agent uninstall`; both also work by hand from an elevated
//! prompt.

use std::ffi::OsString;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use windows_service::service::{
    ServiceAccess, ServiceAction, ServiceActionType, ServiceControl, ServiceControlAccept, ServiceErrorControl,
    ServiceExitCode, ServiceFailureActions, ServiceFailureResetPeriod, ServiceInfo, ServiceStartType, ServiceState,
    ServiceStatus, ServiceType,
};
use windows_service::service_control_handler::{self, ServiceControlHandlerResult};
use windows_service::service_manager::{ServiceManager, ServiceManagerAccess};
use windows_service::{define_windows_service, service_dispatcher};

use pingduck_agent::config::{Config, DEFAULT_PORT};

pub const SERVICE_NAME: &str = "PingDuckAgent";
const DISPLAY_NAME: &str = "PingDuck Agent";
const DESCRIPTION: &str = "Watches this network for PingDuck: finds devices and reports them to your account.";

define_windows_service!(ffi_service_main, service_main);

/// Entry point when the SCM starts us (`pingduck-agent service`).
pub fn run_service() -> windows_service::Result<()> {
    service_dispatcher::start(SERVICE_NAME, ffi_service_main)
}

fn service_main(_args: Vec<OsString>) {
    let stop = Arc::new(AtomicBool::new(false));
    let s = stop.clone();
    let handler = move |control| match control {
        ServiceControl::Stop | ServiceControl::Shutdown => {
            s.store(true, Ordering::Relaxed);
            ServiceControlHandlerResult::NoError
        }
        ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
        _ => ServiceControlHandlerResult::NotImplemented,
    };
    let Ok(status) = service_control_handler::register(SERVICE_NAME, handler) else { return };
    let report = |state, wait| {
        let _ = status.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: state,
            controls_accepted: if state == ServiceState::Running {
                ServiceControlAccept::STOP | ServiceControlAccept::SHUTDOWN
            } else {
                ServiceControlAccept::empty()
            },
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: wait,
            process_id: None,
        });
    };
    report(ServiceState::Running, Duration::default());
    // The service has no console: keep a log next to the state file.
    let dir = Config::from_env().state_dir;
    let _ = std::fs::create_dir_all(&dir);
    pingduck_agent::log::to_file(dir.join("agent.log"));
    crate::run(stop);
    report(ServiceState::Stopped, Duration::default());
}

fn netsh(args: &[&str]) -> bool {
    Command::new("netsh").args(args).output().is_ok_and(|o| o.status.success())
}

fn firewall_rules(exe: &str) -> [(String, String); 2] {
    [
        ("PingDuck Agent (LAN API)".into(), format!("protocol=TCP localport={DEFAULT_PORT}")),
        ("PingDuck Agent (discovery)".into(), format!("protocol=UDP localport=1900 program=\"{exe}\"")),
    ]
}

/// Registers and starts the service, opens the firewall for the phone, and
/// locks the state directory (it holds the agent token) to SYSTEM and Administrators.
pub fn install() -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT | ServiceManagerAccess::CREATE_SERVICE)
        .map_err(|e| format!("open the service manager (run as administrator): {e}"))?;
    let info = ServiceInfo {
        name: SERVICE_NAME.into(),
        display_name: DISPLAY_NAME.into(),
        service_type: ServiceType::OWN_PROCESS,
        start_type: ServiceStartType::AutoStart,
        error_control: ServiceErrorControl::Normal,
        executable_path: exe.clone(),
        launch_arguments: vec!["service".into()],
        dependencies: vec![],
        account_name: None, // LocalSystem
        account_password: None,
    };
    let access = ServiceAccess::CHANGE_CONFIG | ServiceAccess::START | ServiceAccess::QUERY_STATUS;
    let service = match manager.create_service(&info, access) {
        Ok(s) => s,
        // Reinstalling over an existing service (an upgrade): reuse it.
        Err(_) => manager.open_service(SERVICE_NAME, access).map_err(|e| format!("create the service: {e}"))?,
    };
    let _ = service.set_description(DESCRIPTION);
    let _ = service.update_failure_actions(ServiceFailureActions {
        reset_period: ServiceFailureResetPeriod::After(Duration::from_secs(24 * 3600)),
        reboot_msg: None,
        command: None,
        actions: Some(vec![ServiceAction { action_type: ServiceActionType::Restart, delay: Duration::from_secs(10) }; 3]),
    });

    let dir = Config::from_env().state_dir;
    std::fs::create_dir_all(&dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    let dir_s = dir.display().to_string();
    let locked = Command::new("icacls")
        .args([&dir_s, "/inheritance:r", "/grant:r", "*S-1-5-18:(OI)(CI)F", "/grant:r", "*S-1-5-32-544:(OI)(CI)F"])
        .output()
        .is_ok_and(|o| o.status.success());
    if !locked {
        eprintln!("warning: could not restrict {dir_s}");
    }

    let exe_s = exe.display().to_string();
    for (name, rule) in firewall_rules(&exe_s) {
        let _ = netsh(&["advfirewall", "firewall", "delete", "rule", &format!("name={name}")]);
        let mut args = vec!["advfirewall".to_string(), "firewall".into(), "add".into(), "rule".into()];
        args.push(format!("name={name}"));
        args.extend(["dir=in".into(), "action=allow".into(), "profile=private,domain".into()]);
        args.extend(rule.split(' ').map(String::from));
        let refs: Vec<&str> = args.iter().map(String::as_str).collect();
        if !netsh(&refs) {
            eprintln!("warning: could not add the firewall rule \"{name}\"");
        }
    }

    service.start(&[] as &[&str]).or_else(|e| {
        // Already running after a reinstall is fine.
        if service.query_status().is_ok_and(|s| s.current_state == ServiceState::Running) { Ok(()) } else { Err(e) }
    })
    .map_err(|e| format!("start the service: {e}"))?;
    println!("{DISPLAY_NAME} is installed and running.");
    Ok(())
}

/// Stops and removes the service and its firewall rules. Keeps the state
/// directory unless `purge` (the uninstaller's "remove my data").
pub fn uninstall(purge: bool) -> Result<(), String> {
    let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
        .map_err(|e| format!("open the service manager (run as administrator): {e}"))?;
    if let Ok(service) = manager.open_service(SERVICE_NAME, ServiceAccess::STOP | ServiceAccess::DELETE | ServiceAccess::QUERY_STATUS) {
        let _ = service.stop();
        for _ in 0..50 {
            if service.query_status().is_ok_and(|s| s.current_state == ServiceState::Stopped) {
                break;
            }
            std::thread::sleep(Duration::from_millis(200));
        }
        service.delete().map_err(|e| format!("remove the service: {e}"))?;
    }
    let exe = std::env::current_exe().map(|e| e.display().to_string()).unwrap_or_default();
    for (name, _) in firewall_rules(&exe) {
        let _ = netsh(&["advfirewall", "firewall", "delete", "rule", &format!("name={name}")]);
    }
    if purge {
        let _ = std::fs::remove_dir_all(Config::from_env().state_dir);
    }
    println!("{DISPLAY_NAME} is removed.");
    Ok(())
}
