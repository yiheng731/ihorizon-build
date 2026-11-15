//! Horizon on iOS: the ipa's executable.
//!
//! There is no shell here on purpose. `winit` 0.30's iOS backend calls `UIApplicationMain`
//! itself, creates the `UIWindow`/`UIView` and reports `Resumed`/`Suspended` from the app
//! delegate; `wgpu-hal`'s metal backend turns that view's `UiKitWindowHandle` into a
//! `CAMetalLayer` (`third_party/wgpu-hal/src/metal/mod.rs:171`) — so Horizon's own event loop,
//! its surface handling and its renderer run unchanged. What an app has and a desktop does not
//! is a fixed sandbox and no `argv`, and that is all this file adds:
//!
//! 1. `--home` and `--resources` are handed to `horizon-client` through `HORIZON_ARGS`
//!    (`patches/0003-ios-args.patch` reads it in `entry.rs` where it would read `env::args()`).
//! 2. The prepared game files, which need a JVM to make, arrive as a zip the player opens in
//!    Files (`UIFileSharingEnabled`); the first launch that finds one unpacks it into
//!    `Library/Application Support/horizon/resources`, where `--resources` points.
//!
//! Without prepared files Horizon still starts: `game.rs:12295` shows its own "where to get the
//! game files" window, which is the only feedback an app can give before it has any UI.

use std::path::{Path, PathBuf};

/// The prepared files (`horizon-prepare`'s output): the manifest `loading_screen.rs:481` checks.
const RESOURCES_MANIFEST: &str = "horizon-resources.json";

/// On a phone stderr goes nowhere an owner of the phone can read, so the same lines, the panic
/// message with its backtrace, and a heartbeat are appended to `Documents/horizon.log`, which the
/// Files app opens (`UIFileSharingEnabled`). A black window with nothing in this file means the
/// process never reached `main`; a file that stops at one stage says which stage hangs.
static LOG_PATH: std::sync::OnceLock<PathBuf> = std::sync::OnceLock::new();

fn log(message: &str) {
    eprintln!("horizon-ios: {message}");
    let Some(path) = LOG_PATH.get() else { return };
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |since| since.as_millis());
    if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        use std::io::Write;
        let _ = writeln!(file, "{:>9.3}s {message}", stamp as f64 / 1000.0);
    }
}

/// Opens the log, sends panics there, and starts a thread that writes a heartbeat every two
/// seconds: a heartbeat past the last stage means the process is alive and spinning, not dead.
///
/// The heartbeat also copies the client's own `logs/latest.log` out to `Documents/client-latest.log`
/// each time. That file lives under `Library/Application Support`, which the Files app does not
/// show, and it is where `horizon-client` says what it is doing — which screen it is on, whether
/// it found its resources, what it made of the surface.
fn start_logging(documents: &Path, home: &Path) -> PathBuf {
    let path = documents.join("horizon.log");
    let _ = std::fs::write(&path, b"");
    let _ = LOG_PATH.set(path.clone());
    std::panic::set_hook(Box::new(|info| {
        let where_at = info
            .location()
            .map_or_else(String::new, |at| format!(" at {}:{}", at.file(), at.line()));
        let message = info.payload_as_str().unwrap_or("<not a string>");
        log(&format!(
            "PANIC {message}{where_at}\n{}",
            std::backtrace::Backtrace::force_capture()
        ));
    }));
    let client_log = home.join("logs/latest.log");
    let copy_to = documents.join("client-latest.log");
    let copy_to_game = documents.join("game/logs/latest.log");
    std::thread::spawn(move || {
        let started = std::time::Instant::now();
        let mut seen = false;
        loop {
            std::thread::sleep(std::time::Duration::from_millis(500));
            log(&format!("heartbeat {:.1}s", started.elapsed().as_secs_f64()));
            if client_log.is_file() {
                if !seen {
                    seen = true;
                    log(&format!("the client opened {}", client_log.display()));
                }
                let _ = std::fs::copy(&client_log, &copy_to);
                let _ = std::fs::copy(&client_log, &copy_to_game);
            }
        }
    });
    path
}

/// What UIKit says the screen is, logged beside what winit reports.
///
/// `winit`'s iOS backend answers `inner_size` with the safe area times the scale factor and
/// `outer_size` with the screen (`src/platform_impl/ios/window.rs:186`), and on an iPhone 11
/// both came out 16:9 — 2560x1440, a size no iPhone has — with the GUI then laid out for a
/// 427x240 canvas and drawn over the top-left corner of the phone. Which of the two numbers is
/// wrong decides the fix, so the one figure neither of them comes from is logged here.
#[cfg(target_os = "ios")]
fn log_screen() {
    use objc2::msg_send;
    use objc2::runtime::AnyObject;
    use objc2_core_foundation::CGRect;
    // SAFETY: `main` runs on the main thread, before winit takes it; `UIScreen` needs nothing
    // else, and both selectors return a struct by value, which `CGRect` encodes.
    unsafe {
        let screen: *mut AnyObject = msg_send![objc2::class!(UIScreen), mainScreen];
        if screen.is_null() {
            log("screen: UIScreen answered nothing");
            return;
        }
        let bounds: CGRect = msg_send![screen, bounds];
        let native: CGRect = msg_send![screen, nativeBounds];
        let scale: f64 = msg_send![screen, scale];
        log(&format!(
            "screen: bounds {}x{} pt, native {}x{} px, scale {scale}",
            bounds.size.width, bounds.size.height, native.size.width, native.size.height
        ));
        // Measured before UIKit applies the launch orientation, so `bounds` is the portrait
        // figure; this app is landscape only (`Info.plist`), so the long side is the width.
        let long = bounds.size.width.max(bounds.size.height) * scale;
        let short = bounds.size.width.min(bounds.size.height) * scale;
        let window = format!("{}x{}", long.round() as u32, short.round() as u32);
        log(&format!("window: telling horizon-client the screen is {window} px"));
        std::env::set_var("HORIZON_WINDOW", window);
    }
}

/// Off iOS there is no `UIScreen`, and nothing to explain.
#[cfg(not(target_os = "ios"))]
fn log_screen() {}

fn main() {
    // Everything below runs before winit takes the main thread for `UIApplicationMain`.
    let sandbox = sandbox_home();
    let home = app_home(&sandbox);
    let documents = documents_dir(&sandbox);
    let resources = home.join("resources");

    start_logging(&documents, &home);
    log_screen();
    log(&format!(
        "started: pid {} os {} home {} documents {} cwd {}",
        std::process::id(),
        std::env::consts::OS,
        home.display(),
        documents.display(),
        std::env::current_dir().map_or_else(|e| e.to_string(), |d| d.display().to_string()),
    ));

    match import_if_missing(&resources, &documents) {
        Ok(Some(zip)) => log(&format!(
            "imported {} into {}",
            zip.display(),
            resources.display()
        )),
        Ok(None) => log("no zip to import: the prepared files are already there, or none was left in Files"),
        Err(error) => log(&format!("import failed: {error}")),
    }

    // The game folder holds saves, options.txt and packs, and it defaults to the working
    // directory — which for an app bundle is `/`, where nothing may be written
    // (`options.txt is not saved: Operation not permitted (os error 1)`). Point it at
    // `Documents/ihorizon`: everything under Documents is what the Files app shows, so a
    // shaderpack or a resource pack can be dropped in without a computer.
    let game_dir = documents.join("ihorizon");
    if let Err(error) = std::fs::create_dir_all(&game_dir) {
        log(&format!("could not make {}: {error}", game_dir.display()));
    }
    // Older builds kept the folder as `Documents/game`, and older ones still inside the
    // container: bring either over once, so worlds and options are not left behind.
    for (legacy, what) in [
        (documents.join("game"), "Documents/game"),
        (home.join("game"), "the container"),
    ] {
        if game_dir.join("options.txt").is_file() || !legacy.is_dir() {
            continue;
        }
        let _ = std::fs::create_dir_all(&game_dir);
        if let Ok(entries) = std::fs::read_dir(&legacy) {
            for entry in entries.flatten() {
                let target = game_dir.join(entry.file_name());
                if !target.exists() {
                    let _ = std::fs::rename(entry.path(), &target);
                }
            }
            log(&format!("moved the game folder from {what} to Documents/ihorizon"));
        }
    }
    // The folders the game itself reads, made up front so they are there to fill:
    // `mod_list::DIR` is `horizon-mods` (crates/horizon-client-render/src/mod_list.rs:14),
    // not `mods`; `shader_pack_list::DIR` is `shaderpacks`; resource packs are
    // `resourcepacks` (packs/import.rs:117). `saves`, `screenshots` and `logs` are the
    // ones `launch_api.rs:36` lists beside them.
    for name in [
        "shaderpacks",
        "resourcepacks",
        "horizon-mods",
        "logs",
        "saves",
        "screenshots",
    ] {
        let dir = game_dir.join(name);
        if let Err(error) = std::fs::create_dir_all(&dir) {
            log(&format!("could not make {}: {error}", dir.display()));
        }
    }
    install_reimagined(&game_dir);

    let mut args: Vec<String> = vec![
        "--home".into(),
        home.display().to_string(),
        "--game-dir".into(),
        game_dir.display().to_string(),
        // An iPhone 11 has 4 GB in total and iOS kills an app that asks for too much: the
        // desktop default of 12 chunks is more world than this phone can hold.
        "--render-distance".into(),
        std::env::var("HORIZON_RENDER_DISTANCE").unwrap_or_else(|_| "6".into()),
    ];
    if resources.join(RESOURCES_MANIFEST).is_file() {
        args.push("--resources".into());
        args.push(resources.display().to_string());
    } else {
        log(&format!(
            "no {RESOURCES_MANIFEST} in {} — the game shows its own \"where to get the game \
             files\" page",
            resources.display()
        ));
    }
    // Unit separator: one env var can carry any argument, spaces included.
    // Safe: still the only thread — winit starts UIKit's main loop below, not above.
    unsafe {
        std::env::set_var("HORIZON_HOME", &home);
        std::env::set_var("HORIZON_ARGS", args.join("\u{1f}"));
    }

    log(&format!(
        "handing the main thread to horizon-client with HORIZON_ARGS={}",
        args.join(" ")
    ));
    horizon_client::entry::main();
    log("horizon-client returned");
}

/// The app's container root: what iOS exposes as `HOME` (the bundle id's private folder).
fn sandbox_home() -> PathBuf {
    std::env::var_os("HOME").map_or_else(
        || {
            // An app always has HOME; a test run outside one does not.
            eprintln!("horizon-ios: HOME is unset, using the working directory");
            PathBuf::from(".")
        },
        PathBuf::from,
    )
}

/// `Library/Application Support/horizon`, the folder the desktop build keeps in the platform's
/// data directory (`horizon-client-render/src/logging.rs:113`). Logs land here too.
fn app_home(sandbox: &Path) -> PathBuf {
    let home = sandbox.join("Library/Application Support/horizon");
    let _ = std::fs::create_dir_all(&home);
    home
}

/// The app's Documents folder: what `UIFileSharingEnabled` shows in Files. When the launcher
/// changes, this is where the player drops the prepared zip.
fn documents_dir(sandbox: &Path) -> PathBuf {
    sandbox.join("Documents")
}

/// Unpacks the newest `*.zip` in `documents` when the prepared files are not there yet.
///
/// The archive is `horizon-prepare`'s output folder, possibly inside one directory (a zip made
/// by right-clicking the folder): every entry names `assets/…`, `data/…` or
/// `horizon-resources.json`, and one shared leading directory is dropped so `--resources` lands
/// on the manifest.
fn import_if_missing(resources: &Path, documents: &Path) -> Result<Option<PathBuf>, String> {
    let zip = newest_zip(documents)?;
    // A newer zip in Files replaces the prepared files already in place: the game ships
    // none of its own, so a fixed build gets its new resources the same way the first one
    // did, by being dropped here and the app started again.
    let manifest = resources.join(RESOURCES_MANIFEST);
    if manifest.is_file() {
        let Some(zip) = zip.as_ref() else {
            return Ok(None);
        };
        let imported = std::fs::metadata(&manifest)
            .and_then(|m| m.modified())
            .ok();
        let written = std::fs::metadata(zip).and_then(|m| m.modified()).ok();
        if !matches!((imported, written), (Some(i), Some(w)) if w > i) {
            return Ok(None);
        }
    }
    let Some(zip) = zip else {
        return Ok(None);
    };
    let file = std::fs::File::open(&zip).map_err(|e| format!("{}: {e}", zip.display()))?;
    let mut archive =
        zip::ZipArchive::new(file).map_err(|e| format!("{}: {e}", zip.display()))?;

    let stripped = shared_prefix(&mut archive);
    // Unpack beside the target and rename at the end: a kill mid-copy must not leave a
    // half-written folder that the manifest check accepts.
    let staging = resources.with_extension("incoming");
    let _ = std::fs::remove_dir_all(&staging);
    std::fs::create_dir_all(&staging).map_err(|e| format!("{}: {e}", staging.display()))?;

    for index in 0..archive.len() {
        let mut entry = archive
            .by_index(index)
            .map_err(|e| format!("entry {index}: {e}"))?;
        let Some(relative) = entry.enclosed_name() else {
            continue;
        };
        // One shared leading directory in the archive (`horizon-client-26.3/assets/…`) is
        // dropped so the manifest ends up directly in `resources`.
        let relative = if stripped.as_os_str().is_empty() {
            relative
        } else {
            match relative.strip_prefix(&stripped) {
                Ok(rest) => rest.to_path_buf(),
                Err(_) => relative.clone(),
            }
        };
        if relative.as_os_str().is_empty() {
            continue;
        }
        let target = staging.join(&relative);
        if entry.is_dir() {
            let _ = std::fs::create_dir_all(&target);
            continue;
        }
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?;
        }
        let mut out =
            std::fs::File::create(&target).map_err(|e| format!("{}: {e}", target.display()))?;
        std::io::copy(&mut entry, &mut out).map_err(|e| format!("{}: {e}", target.display()))?;
    }

    if !staging.join(RESOURCES_MANIFEST).is_file() {
        // A zip of the wrong thing: keep it, and let the next start try another.
        let _ = std::fs::remove_dir_all(&staging);
        return Err(format!(
            "{} has no {RESOURCES_MANIFEST}: it is not horizon-prepare's output",
            zip.display()
        ));
    }
    let _ = std::fs::remove_dir_all(resources);
    std::fs::rename(&staging, resources)
        .map_err(|e| format!("{} -> {}: {e}", staging.display(), resources.display()))?;
    Ok(Some(zip))
}

/// The one directory every entry sits under, if there is one (`horizon-client-26.3/assets/…`).
fn shared_prefix(archive: &mut zip::ZipArchive<std::fs::File>) -> PathBuf {
    let mut shared: Option<PathBuf> = None;
    for index in 0..archive.len() {
        let Ok(entry) = archive.by_index_raw(index) else {
            return PathBuf::new();
        };
        let Some(name) = entry.enclosed_name() else {
            return PathBuf::new();
        };
        let mut parts = name.components();
        let Some(first) = parts.next() else {
            return PathBuf::new();
        };
        // A file at the top - `horizon-resources.json` itself - means nothing is stripped.
        if parts.next().is_none() && entry.is_file() {
            return PathBuf::new();
        }
        let first = PathBuf::from(first.as_os_str());
        match &shared {
            None => shared = Some(first),
            Some(known) if known == &first => {}
            Some(_) => return PathBuf::new(),
        }
    }
    shared.unwrap_or_default()
}

fn newest_zip(documents: &Path) -> Result<Option<PathBuf>, String> {
    let entries = match std::fs::read_dir(documents) {
        Ok(entries) => entries,
        // No Documents folder is not an error: nothing to import.
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(format!("{}: {error}", documents.display())),
    };
    let mut best: Option<(std::time::SystemTime, PathBuf)> = None;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|ext| ext != "zip") {
            continue;
        }
        let modified = entry
            .metadata()
            .and_then(|meta| meta.modified())
            .unwrap_or(std::time::UNIX_EPOCH);
        if best.as_ref().is_none_or(|(when, _)| modified > *when) {
            best = Some((modified, path));
        }
    }
    Ok(best.map(|(_, path)| path))
}

/// The pack this build ships: Complementary Reimagined's sky and light rewritten for Horizon's
/// own stage API (`horizon-shader check` reports 0 problems, 1504 expressions across four
/// stages). It is written into the player's `shaderpacks/` on first launch, so the pack can be
/// picked without a file transfer; a file already there is left alone, edits included.
const REIMAGINED: &[(&str, &str)] = &[
    (
        "horizon-shaders.toml",
        include_str!("../assets/shaderpacks/reimagined/horizon-shaders.toml"),
    ),
    (
        "common.wgsl",
        include_str!("../assets/shaderpacks/reimagined/common.wgsl"),
    ),
    (
        "sky.wgsl",
        include_str!("../assets/shaderpacks/reimagined/sky.wgsl"),
    ),
    (
        "material.wgsl",
        include_str!("../assets/shaderpacks/reimagined/material.wgsl"),
    ),
    (
        "post/bloom.wgsl",
        include_str!("../assets/shaderpacks/reimagined/post/bloom.wgsl"),
    ),
    (
        "post/grade.wgsl",
        include_str!("../assets/shaderpacks/reimagined/post/grade.wgsl"),
    ),
];

fn install_reimagined(game_dir: &Path) {
    let root = game_dir.join("shaderpacks").join("reimagined");
    for (name, body) in REIMAGINED {
        let path = root.join(name);
        if path.is_file() {
            continue;
        }
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        if let Err(error) = std::fs::write(&path, body) {
            log(&format!("could not write {}: {error}", path.display()));
        }
    }
    log(&format!("shader pack reimagined at {}", root.display()));
}
