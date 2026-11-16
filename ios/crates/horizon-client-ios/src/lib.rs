use std::path::{Path, PathBuf};

const RESOURCES_MANIFEST: &str = "horizon-resources.json";

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

#[cfg(target_os = "ios")]
fn log_screen() {
    use objc2::msg_send;
    use objc2::runtime::AnyObject;
    use objc2_core_foundation::CGRect;
    
    
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
        
        
        let long = bounds.size.width.max(bounds.size.height) * scale;
        let short = bounds.size.width.min(bounds.size.height) * scale;
        let window = format!("{}x{}", long.round() as u32, short.round() as u32);
        log(&format!("window: telling horizon-client the screen is {window} px"));
        std::env::set_var("HORIZON_WINDOW", window);
    }
}

#[cfg(not(target_os = "ios"))]
fn log_screen() {}

#[unsafe(no_mangle)]
pub extern "C" fn hz_run() {
    
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

    
    
    
    
    
    let game_dir = documents.join("game");
    if let Err(error) = std::fs::create_dir_all(&game_dir) {
        log(&format!("could not make {}: {error}", game_dir.display()));
    }
    
    
    let legacy = home.join("game");
    if !game_dir.join("options.txt").is_file() && legacy.is_dir() {
        let _ = std::fs::create_dir_all(&game_dir);
        if let Ok(entries) = std::fs::read_dir(&legacy) {
            for entry in entries.flatten() {
                let target = game_dir.join(entry.file_name());
                if !target.exists() {
                    let _ = std::fs::rename(entry.path(), &target);
                }
            }
            log("moved the game folder from the container into Documents");
        }
    }
    
    
    
    
    
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

fn sandbox_home() -> PathBuf {
    std::env::var_os("HOME").map_or_else(
        || {
            
            eprintln!("horizon-ios: HOME is unset, using the working directory");
            PathBuf::from(".")
        },
        PathBuf::from,
    )
}

fn app_home(sandbox: &Path) -> PathBuf {
    let home = sandbox.join("Library/Application Support/horizon");
    let _ = std::fs::create_dir_all(&home);
    home
}

fn documents_dir(sandbox: &Path) -> PathBuf {
    sandbox.join("Documents")
}

fn import_if_missing(resources: &Path, documents: &Path) -> Result<Option<PathBuf>, String> {
    let zip = newest_zip(documents)?;
    
    
    
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

#[unsafe(no_mangle)]
pub extern "C" fn hz_input(line: *const std::ffi::c_char) {
    if line.is_null() {
        return;
    }
    
    
    if let Ok(text) = unsafe { std::ffi::CStr::from_ptr(line) }.to_str() {
        horizon_threads::ios_commands::push(text.to_owned());
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hz_launcher_closing() {
    ok_log("the launcher is closed");
}

fn ok_log(message: &str) {
    log(message);
}
