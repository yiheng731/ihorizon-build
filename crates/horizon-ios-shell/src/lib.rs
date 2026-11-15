

#![deny(clippy::undocumented_unsafe_blocks)]

use core::ffi::{c_char, c_void};
use std::ffi::CStr;
use std::path::Path;
use std::sync::{Mutex, OnceLock};

const TOUCH_BEGAN: u32 = 0;

pub struct Shell {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    pipeline: wgpu::RenderPipeline,
    scale: f32,
    frames: u64,
    last_dt: f32,
    touches: Vec<(u32, u32, f32, f32)>,
    
    adapter: std::ffi::CString,
}

static LAST_ERROR: OnceLock<Mutex<String>> = OnceLock::new();

fn last_error_slot() -> &'static Mutex<String> {
    LAST_ERROR.get_or_init(|| Mutex::new(String::new()))
}

fn set_error(message: impl Into<String>) {
    let message = message.into();
    eprintln!("horizon-ios: {message}");
    if let Ok(mut slot) = last_error_slot().lock() {
        *slot = message;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hz_last_error() -> *const c_char {
    
    
    static BUFFER: OnceLock<Mutex<std::ffi::CString>> = OnceLock::new();
    let text = last_error_slot()
        .lock()
        .map(|s| s.clone())
        .unwrap_or_default();
    let buffer = BUFFER.get_or_init(|| Mutex::new(std::ffi::CString::new("").unwrap()));
    let mut guard = buffer.lock().unwrap();
    *guard = std::ffi::CString::new(text).unwrap_or_default();
    guard.as_ptr()
}

fn block_on<F: Future>(future: F) -> F::Output {
    use std::sync::Arc;
    use std::task::{Context, Poll, Wake, Waker};

    struct ThreadWaker(std::thread::Thread);
    impl Wake for ThreadWaker {
        fn wake(self: Arc<Self>) {
            self.0.unpark();
        }
        fn wake_by_ref(self: &Arc<Self>) {
            self.0.unpark();
        }
    }

    let waker = Waker::from(Arc::new(ThreadWaker(std::thread::current())));
    let mut cx = Context::from_waker(&waker);
    let mut future = std::pin::pin!(future);
    loop {
        match future.as_mut().poll(&mut cx) {
            Poll::Ready(value) => return value,
            Poll::Pending => std::thread::park(),
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_create(
    layer: *mut c_void,
    width: u32,
    height: u32,
    scale: f32,
) -> *mut Shell {
    std::panic::set_hook(Box::new(|info| {
        eprintln!("horizon-ios panic: {info}");
    }));

    if layer.is_null() {
        set_error("hz_create: null CAMetalLayer");
        return std::ptr::null_mut();
    }
    let (width, height) = (width.max(1), height.max(1));

    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::METAL,
        flags: wgpu::InstanceFlags::default(),
        memory_budget_thresholds: wgpu::MemoryBudgetThresholds::default(),
        backend_options: wgpu::BackendOptions::default(),
        display: None,
    });

    
    let surface = match unsafe {
        instance.create_surface_unsafe(wgpu::SurfaceTargetUnsafe::CoreAnimationLayer(layer))
    } {
        Ok(surface) => surface,
        Err(error) => {
            set_error(format!("create_surface(CoreAnimationLayer): {error}"));
            return std::ptr::null_mut();
        }
    };

    let adapter = match block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        force_fallback_adapter: false,
        compatible_surface: Some(&surface),
        apply_limit_buckets: false,
    })) {
        Ok(adapter) => adapter,
        Err(error) => {
            set_error(format!("request_adapter: {error}"));
            return std::ptr::null_mut();
        }
    };

    let (device, queue) = match block_on(adapter.request_device(&wgpu::DeviceDescriptor {
        label: Some("horizon-ios"),
        required_features: wgpu::Features::empty(),
        required_limits: wgpu::Limits::downlevel_defaults().using_resolution(adapter.limits()),
        experimental_features: wgpu::ExperimentalFeatures::disabled(),
        memory_hints: wgpu::MemoryHints::Performance,
        trace: wgpu::Trace::Off,
    })) {
        Ok(pair) => pair,
        Err(error) => {
            set_error(format!("request_device: {error}"));
            return std::ptr::null_mut();
        }
    };

    
    
    let Some(mut config) = surface.get_default_config(&adapter, width, height) else {
        set_error("surface has no default configuration");
        return std::ptr::null_mut();
    };
    config.width = width;
    config.height = height;
    config.present_mode = wgpu::PresentMode::Fifo;
    config.desired_maximum_frame_latency = 2;
    let format = config.format;
    surface.configure(&device, &config);

    let pipeline = build_probe_pipeline(&device, format);

    eprintln!(
        "horizon-ios: adapter {:?}, format {format:?}, {width}x{height} @{scale}x",
        adapter.get_info()
    );

    let info = adapter.get_info();
    let adapter_label = format!("{} / {:?}", info.name, info.backend);
    let shell = Box::new(Shell {
        surface,
        device,
        queue,
        config,
        pipeline,
        scale,
        frames: 0,
        last_dt: 0.0,
        touches: Vec::with_capacity(16),
        adapter: std::ffi::CString::new(adapter_label).unwrap_or_default(),
    });
    Box::into_raw(shell)
}

fn build_probe_pipeline(device: &wgpu::Device, format: wgpu::TextureFormat) -> wgpu::RenderPipeline {
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("horizon-ios probe"),
        source: wgpu::ShaderSource::Wgsl(
            r#"
@vertex
fn vs_main(@builtin(vertex_index) index: u32) -> @builtin(position) vec4<f32> {
    var positions = array<vec2<f32>, 3>(
        vec2<f32>( 0.0,  0.6),
        vec2<f32>(-0.6, -0.5),
        vec2<f32>( 0.6, -0.5),
    );
    return vec4<f32>(positions[index], 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4<f32> {
    return vec4<f32>(0.36, 0.72, 0.45, 1.0);
}
"#
            .into(),
        ),
    });

    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("horizon-ios probe layout"),
        bind_group_layouts: &[],
        immediate_size: 0,
    });

    device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("horizon-ios probe pipeline"),
        layout: Some(&layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: Some("vs_main"),
            compilation_options: Default::default(),
            buffers: &[],
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: Some("fs_main"),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState {
                format,
                blend: None,
                write_mask: wgpu::ColorWrites::ALL,
            })],
        }),
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview_mask: None,
        cache: None,
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_adapter_info(shell: *mut Shell) -> *const c_char {
    unsafe { shell.as_ref() }.map_or(std::ptr::null(), |s| s.adapter.as_ptr())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_destroy(shell: *mut Shell) {
    if shell.is_null() {
        return;
    }
    
    drop(unsafe { Box::from_raw(shell) });
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_resize(shell: *mut Shell, width: u32, height: u32) {
    let Some(shell) = (unsafe { shell.as_mut() }) else {
        return;
    };
    let (width, height) = (width.max(1), height.max(1));
    if shell.config.width == width && shell.config.height == height {
        return;
    }
    shell.config.width = width;
    shell.config.height = height;
    shell.surface.configure(&shell.device, &shell.config);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_frame(shell: *mut Shell, dt: f32) {
    let Some(shell) = (unsafe { shell.as_mut() }) else {
        return;
    };
    shell.last_dt = dt;
    shell.frames += 1;

    let frame = match shell.surface.get_current_texture() {
        wgpu::CurrentSurfaceTexture::Success(frame) => frame,
        wgpu::CurrentSurfaceTexture::Suboptimal(frame) => {
            
            shell.surface.configure(&shell.device, &shell.config);
            frame
        }
        
        wgpu::CurrentSurfaceTexture::Lost | wgpu::CurrentSurfaceTexture::Outdated => {
            shell.surface.configure(&shell.device, &shell.config);
            return;
        }
        wgpu::CurrentSurfaceTexture::Timeout | wgpu::CurrentSurfaceTexture::Occluded => return,
        wgpu::CurrentSurfaceTexture::Validation => {
            set_error("surface validation error");
            return;
        }
    };

    let view = frame
        .texture
        .create_view(&wgpu::TextureViewDescriptor::default());
    let mut encoder = shell
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("horizon-ios frame"),
        });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("horizon-ios pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    
                    
                    load: wgpu::LoadOp::Clear({
                        let pulse = (shell.frames as f64 * 0.03).sin() * 0.5 + 0.5;
                        wgpu::Color {
                            r: 0.03 + pulse * 0.10,
                            g: 0.04 + pulse * 0.28,
                            b: 0.06 + pulse * 0.12,
                            a: 1.0,
                        }
                    }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        pass.set_pipeline(&shell.pipeline);
        pass.draw(0..3, 0..1);
    }
    shell.queue.submit(Some(encoder.finish()));
    
    shell.queue.present(frame);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_frame_count(shell: *mut Shell) -> u64 {
    unsafe { shell.as_ref() }.map_or(0, |s| s.frames)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_scale(shell: *mut Shell) -> f32 {
    unsafe { shell.as_ref() }.map_or(1.0, |s| s.scale)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_touch(shell: *mut Shell, id: u32, phase: u32, x: f32, y: f32) {
    let Some(shell) = (unsafe { shell.as_mut() }) else {
        return;
    };
    if phase == TOUCH_BEGAN {
        shell.touches.push((id, phase, x, y));
    } else if let Some(slot) = shell.touches.iter_mut().find(|t| t.0 == id) {
        *slot = (id, phase, x, y);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_set_assets_root(utf8_path: *const c_char) -> bool {
    if utf8_path.is_null() {
        set_error("hz_set_assets_root: null path");
        return false;
    }
    
    let path = unsafe { CStr::from_ptr(utf8_path) }
        .to_string_lossy()
        .into_owned();
    let state = assets_state(Path::new(&path));
    if state != 0 {
        set_error(format!("assets not ready at {path} (state {state})"));
        return false;
    }
    ASSETS_ROOT
        .get_or_init(|| Mutex::new(None))
        .lock()
        .unwrap()
        .replace(path);
    true
}

static ASSETS_ROOT: OnceLock<Mutex<Option<String>>> = OnceLock::new();

#[unsafe(no_mangle)]
pub extern "C" fn hz_assets_root() -> *const c_char {
    static BUFFER: OnceLock<Mutex<std::ffi::CString>> = OnceLock::new();
    let text = ASSETS_ROOT
        .get()
        .and_then(|slot| slot.lock().ok().and_then(|guard| guard.clone()))
        .unwrap_or_default();
    let buffer = BUFFER.get_or_init(|| Mutex::new(std::ffi::CString::new("").unwrap()));
    let mut guard = buffer.lock().unwrap();
    *guard = std::ffi::CString::new(text).unwrap_or_default();
    guard.as_ptr()
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn hz_assets_state(utf8_path: *const c_char) -> i32 {
    if utf8_path.is_null() {
        return 1;
    }
    
    let path = unsafe { CStr::from_ptr(utf8_path) }
        .to_string_lossy()
        .into_owned();
    assets_state(Path::new(&path))
}

fn assets_state(root: &Path) -> i32 {
    if !root.is_dir() {
        return 1;
    }
    if !root.join("assets").is_dir() {
        return 2;
    }
    if !root.join("data").is_dir() {
        return 3;
    }
    0
}
