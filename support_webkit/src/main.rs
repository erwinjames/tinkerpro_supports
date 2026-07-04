// TinkerPro Support — minimal bare-WebKitGTK desktop wrapper.
//
// This deliberately does NOT use Tauri/wry: on Linux, wry's IPC/custom-protocol
// layer maxes out WebKitGTK's connection pool and hangs heavy remote sites
// (tauri-apps/tauri#8922). A plain WebKitWebView (what MiniBrowser uses) loads
// the dashboard fine, so we wrap that directly.

use gtk::gio;
use gtk::glib;
use gtk::prelude::*;
use webkit2gtk::{
    NavigationPolicyDecision, NavigationPolicyDecisionExt, PolicyDecisionExt, PolicyDecisionType,
    SettingsExt, URIRequestExt, WebView, WebViewExt,
};

const START_URL: &str = "https://support.tinkerpro.io";

/// Hosts allowed to open INSIDE the app window. Everything else is handed to
/// the system browser. OAuth provider hosts stay in-app so social login works.
fn is_internal_host(host: &str) -> bool {
    host.ends_with("tinkerpro.io")
        || host.ends_with("tinkerpro.cloud")
        || host == "localhost"
        || host == "127.0.0.1"
        || host == "accounts.google.com"
        || host == "oauth2.googleapis.com"
        || host.ends_with(".googleusercontent.com")
        || host.ends_with("facebook.com")
        || host.ends_with("microsoftonline.com")
        || host.ends_with("live.com")
        || host == "github.com"
}

fn host_of(url: &str) -> Option<String> {
    // Cheap host extractor: scheme://host/...
    let after_scheme = url.split("://").nth(1)?;
    let host = after_scheme.split(['/', '?', '#']).next()?;
    let host = host.split('@').last()?; // strip userinfo
    let host = host.split(':').next()?; // strip port
    Some(host.to_ascii_lowercase())
}

fn open_external(url: &str) {
    // Route to the user's default browser. xdg-open is present on any desktop.
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

fn main() {
    // WebKitGTK's DMABUF renderer paints a blank/white webview on many Linux
    // GPU/driver combos; disabling just that path keeps hardware acceleration.
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1");
    }

    // Optional override for testing (e.g. TINKERPRO_URL=http://localhost/...).
    let start_url = std::env::var("TINKERPRO_URL").unwrap_or_else(|_| START_URL.to_string());

    if gtk::init().is_err() {
        eprintln!("Failed to initialize GTK.");
        std::process::exit(1);
    }

    // App/window icon. Try a few well-known install locations; harmless if none
    // exist (dev runs). The .desktop file drives the taskbar icon in packaging.
    for path in [
        "/usr/share/icons/hicolor/256x256/apps/tinkerpro-support.png",
        "/app/share/icons/tinkerpro-support.png",
        concat!(env!("CARGO_MANIFEST_DIR"), "/assets/icon.png"),
    ] {
        if std::path::Path::new(path).exists() {
            let _ = gtk::Window::set_default_icon_from_file(path);
            break;
        }
    }

    let window = gtk::Window::new(gtk::WindowType::Toplevel);
    window.set_title("TinkerPro Support");
    window.set_default_size(1280, 800);

    let webview = WebView::new();

    if let Some(settings) = WebViewExt::settings(&webview) {
        settings.set_enable_developer_extras(true);
        settings.set_javascript_can_open_windows_automatically(true);
        settings.set_enable_write_console_messages_to_stdout(false);
    }

    // Open non-app links in the system browser instead of trapping them here.
    webview.connect_decide_policy(|_wv, decision, decision_type| {
        let is_nav = matches!(
            decision_type,
            PolicyDecisionType::NavigationAction | PolicyDecisionType::NewWindowAction
        );
        if !is_nav {
            return false;
        }
        if let Some(nav) = decision.downcast_ref::<NavigationPolicyDecision>() {
            if let Some(uri) = nav
                .navigation_action()
                .and_then(|a| a.request())
                .and_then(|r| r.uri())
            {
                let uri = uri.to_string();
                if uri.starts_with("http") {
                    let internal = host_of(&uri).map(|h| is_internal_host(&h)).unwrap_or(true);
                    if !internal {
                        open_external(&uri);
                        decision.ignore();
                        return true;
                    }
                }
            }
        }
        false
    });

    webview.load_uri(&start_url);
    window.add(&webview);

    window.connect_delete_event(|_, _| {
        gtk::main_quit();
        glib::Propagation::Proceed
    });

    window.show_all();
    let _ = gio::Cancellable::NONE; // keep gio import used across gtk-rs versions
    gtk::main();
}
