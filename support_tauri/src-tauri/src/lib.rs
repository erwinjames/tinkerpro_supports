use tauri::{WebviewUrl, WebviewWindowBuilder};
use tauri_plugin_opener::OpenerExt;

/// Hosts that are allowed to load INSIDE the app window.
///
/// Everything else (external links, "open in new tab") is handed off to the
/// user's default browser instead of trapping them inside the frameless app.
/// OAuth provider hosts must stay in-app so social-login redirects can
/// complete and land back on support.tinkerpro.io.
fn is_internal_host(host: &str) -> bool {
    host.ends_with("tinkerpro.io")            // the app itself
        || host.ends_with("tinkerpro.cloud")  // tinker-chat realtime
        || host == "accounts.google.com"      // Google OAuth
        || host == "oauth2.googleapis.com"
        || host.ends_with(".googleusercontent.com")
        || host.ends_with("facebook.com")     // Facebook OAuth
        || host.ends_with("microsoftonline.com") // Microsoft OAuth
        || host.ends_with("live.com")
        || host == "github.com" // GitHub OAuth
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let handle = app.handle().clone();
            WebviewWindowBuilder::new(
                app,
                "main",
                WebviewUrl::External(
                    "https://support.tinkerpro.io"
                        .parse()
                        .expect("valid start URL"),
                ),
            )
            .title("TinkerPro Support")
            .inner_size(1280.0, 800.0)
            .min_inner_size(900.0, 600.0)
            .resizable(true)
            .center()
            .on_navigation(move |url| {
                // Only ever intercept real web navigations.
                if url.scheme() != "http" && url.scheme() != "https" {
                    return true;
                }
                let host = url.host_str().unwrap_or("").to_ascii_lowercase();
                if is_internal_host(&host) {
                    return true; // keep it in the app
                }
                // External destination: open in the system browser and
                // cancel the in-app navigation.
                let _ = handle.opener().open_url(url.as_str(), None::<&str>);
                false
            })
            .build()?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
