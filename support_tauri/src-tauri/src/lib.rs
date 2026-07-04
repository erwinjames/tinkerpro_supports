use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};
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
    // WebKitGTK's DMABUF renderer produces a blank/white webview on many Linux
    // GPU/driver combos (the page loads but never paints). Disabling just that
    // path fixes rendering while KEEPING hardware acceleration — much faster
    // than WEBKIT_DISABLE_COMPOSITING_MODE, which falls back to software.
    // Only set it if the user hasn't overridden it. Linux-only; no-op elsewhere.
    #[cfg(target_os = "linux")]
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }

    // Start URL is overridable via TINKERPRO_URL for testing (e.g. a local
    // server); defaults to the live site.
    let start_url = std::env::var("TINKERPRO_URL")
        .unwrap_or_else(|_| "https://support.tinkerpro.io".to_string());

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .setup(move |app| {
            let handle = app.handle().clone();
            WebviewWindowBuilder::new(
                app,
                "main",
                WebviewUrl::External(start_url.parse().expect("valid start URL")),
            )
            .title("TinkerPro Support")
            .inner_size(1280.0, 800.0)
            .min_inner_size(900.0, 600.0)
            .resizable(true)
            .center()
            .on_navigation(move |url| {
                // Non-app links open in the system browser instead of trapping
                // the user in the app window. OAuth hosts stay in-app.
                if url.scheme() != "http" && url.scheme() != "https" {
                    return true;
                }
                let host = url.host_str().unwrap_or("").to_ascii_lowercase();
                if is_internal_host(&host) {
                    return true;
                }
                let _ = handle.opener().open_url(url.as_str(), None::<&str>);
                false
            })
            .build()?;

            // Launch with TINKERPRO_DEVTOOLS=1 to auto-open the WebKit inspector.
            #[cfg(all(feature = "devtools", target_os = "linux"))]
            if std::env::var_os("TINKERPRO_DEVTOOLS").is_some() {
                if let Some(w) = app.get_webview_window("main") {
                    w.open_devtools();
                }
            }

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
