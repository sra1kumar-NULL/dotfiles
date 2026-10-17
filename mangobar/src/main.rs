mod clock;
mod mango_ipc;
mod mmsg;
mod palette;
mod settings;
mod status;
mod sysstate;
mod tags;
mod theme;
mod tray;
mod volume;

use gtk::gio;
use gtk::glib::{self, ControlFlow, LogLevel, LogWriterOutput};
use gtk::prelude::*;
use gtk::{Application, ApplicationWindow, CssProvider, Label, Orientation};
use gtk4_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};
use mango_ipc::MangoEvent;
use settings::*;
use status::Modules;
use std::cell::RefCell;
use std::collections::HashMap;
use std::env;
use std::rc::Rc;
use std::sync::mpsc;
use std::time::Duration;
use tokio::runtime::Handle;
use tokio::sync::watch;

pub use tags::Tag;

#[derive(Clone, Debug, Default)]
struct Args {
    output: Option<String>,
}

fn main() -> glib::ExitCode {
    // First thing: SIGUSR1's default action is to terminate, and theme scripts
    // may signal a bar that is still starting up.
    theme::install_sigusr1();
    quiet_gtk();
    install_log_filter();

    let args = parse_args();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .enable_time()
        .build()
        .expect("failed to start tokio runtime");
    let handle = runtime.handle().clone();

    std::thread::spawn(move || runtime.block_on(std::future::pending::<()>()));

    // NON_UNIQUE: one bar per monitor means several processes share this
    // application id, and GApplication's default single-instance behaviour makes
    // every instance after the first hand off to the primary one and exit.
    let app = Application::builder()
        .application_id(APP_ID)
        .flags(gio::ApplicationFlags::NON_UNIQUE)
        .build();
    app.connect_activate(move |app| build_ui(app, args.clone(), handle.clone()));
    // parse_args() has already taken --output, but GApplication parses argv too
    // and bails with "Unknown option --output", so hand it only a program name.
    app.run_with_args(&["mangobar"])
}

fn quiet_gtk() {
    unsafe {
        env::set_var("GTK_USE_PORTAL", "0");
        env::set_var("GSK_RENDERER", "cairo");
        env::remove_var("G_MESSAGES_DEBUG");
        env::remove_var("GDK_DEBUG");
        env::remove_var("GSK_DEBUG");
    }
}

fn install_log_filter() {
    glib::log_set_writer_func(|level, fields| {
        if matches!(level, LogLevel::Debug | LogLevel::Info) {
            return LogWriterOutput::Handled;
        }

        let mut domain = None;
        let mut message = None;

        for field in fields {
            match field.key() {
                "GLIB_DOMAIN" => domain = field.value_str(),
                "MESSAGE" => message = field.value_str(),
                _ => {}
            }
        }

        if level == LogLevel::Warning
            && domain == Some("Gdk")
            && message.is_some_and(|msg| {
                msg.contains("Cannot get portal org.freedesktop.portal.Inhibit version")
            })
        {
            return LogWriterOutput::Handled;
        }

        glib::log_writer_standard_streams(level, fields)
    });
}

fn parse_args() -> Args {
    let mut args = Args::default();
    let mut iter = env::args().skip(1);

    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "-o" | "--output" => args.output = iter.next(),
            "-h" | "--help" => {
                println!("Usage: mangobar [--output <name>]");
                std::process::exit(0);
            }
            unknown => eprintln!("mangobar: ignoring unknown argument: {unknown}"),
        }
    }

    args
}

fn build_ui(app: &Application, args: Args, handle: Handle) {
    let css = install_css();

    // --output has to reach the layer surface, not just the IPC filter: upstream
    // only used it to pick which monitor's tags to show, so two instances both
    // landed on whichever output the compositor chose and one screen got no bar.
    let monitor = gdk_monitor(args.output.as_deref());
    let width = logical_width(args.output.as_deref());
    let (ipc_tx, ipc_rx) = mpsc::channel::<MangoEvent>();
    let (status_tx, status_rx) = mpsc::channel::<Modules>();
    let tags = Rc::new(RefCell::new(Vec::<Tag>::new()));

    let window = build_window(app, width, monitor.as_ref());
    let root = build_root(width);
    let tags_box = gtk::Box::new(Orientation::Horizontal, 0);
    let spacer = gtk::Box::new(Orientation::Horizontal, 0);
    let modules_box = gtk::Box::new(Orientation::Horizontal, 0);

    tags_box.add_css_class("tags");
    spacer.set_hexpand(true);
    spacer.add_css_class("bar");
    modules_box.add_css_class("modules");
    modules_box.set_halign(gtk::Align::End);

    // Read-only on purpose: nothing on the bar reacts to the pointer except the
    // tray. Menus and workspace switching live on keybinds.
    let volume = module_label();
    let battery = module_label();
    let clock = module_label();

    // Indicator strip, omarchy-style: icon-only, and everything except the
    // network glyph hides itself when off so it takes no space.
    let indicators_box = gtk::Box::new(Orientation::Horizontal, 0);
    indicators_box.add_css_class("indicators");
    let ind_network = indicator_label();
    let ind_bluetooth = indicator_label();
    let ind_dnd = indicator_label();
    let ind_recording = indicator_label();
    let ind_night = indicator_label();
    let ind_awake = indicator_label();
    ind_recording.add_css_class("recording");
    set_module(&ind_dnd, &status::indicator::DND.to_string());
    set_module(&ind_recording, &status::indicator::RECORDING.to_string());
    set_module(&ind_night, &status::indicator::NIGHT.to_string());
    set_module(&ind_awake, &status::indicator::AWAKE.to_string());
    for label in [
        &ind_recording,
        &ind_dnd,
        &ind_awake,
        &ind_night,
        &ind_bluetooth,
        &ind_network,
    ] {
        indicators_box.append(label);
    }
    // Tray sits left of the indicators. Unlike the rest of the bar it is
    // clickable: left = activate the app, right = the app's own menu.
    let tray_box = gtk::Box::new(Orientation::Horizontal, 0);
    tray_box.add_css_class("tray");
    modules_box.append(&tray_box);
    let (tray_rx, tray_cmd) = tray::spawn(&handle);
    let mut tray_buttons: HashMap<String, gtk::Button> = HashMap::new();

    modules_box.append(&indicators_box);

    for label in [&volume, &battery, &clock] {
        modules_box.append(label);
    }

    root.append(&tags_box);
    root.append(&spacer);
    root.append(&modules_box);

    window.set_child(Some(&root));
    window.present();

    if let Ok(initial) = load_tags(args.output.as_deref()) {
        render_tags(&tags_box, &tags, initial);
    }

    mango_ipc::spawn(args.output.clone(), ipc_tx);
    spawn_status(&handle, status_tx);

    glib::timeout_add_local(Duration::from_millis(UI_TICK_MS), move || {
        // SIGUSR1 sets a flag; the reload itself happens here on the main thread.
        if theme::take_reload() {
            theme::load(&css);
        }

        while let Ok(event) = ipc_rx.try_recv() {
            let MangoEvent::Tags(next) = event;
            render_tags(&tags_box, &tags, next);
        }

        while let Ok(event) = tray_rx.try_recv() {
            handle_tray_event(event, &tray_box, &mut tray_buttons, &tray_cmd);
        }

        while let Ok(modules) = status_rx.try_recv() {
            set_module(&volume, &modules.volume.label());
            // A machine with no battery gets an empty label; hide the button
            // rather than leaving a dead gap between sound and the clock.
            battery.set_visible(!modules.battery.text.is_empty());
            set_module(&battery, &modules.battery.label());
            set_module(&clock, &modules.clock.label());

            let ind = modules.indicators;
            set_module(&ind_network, &status::indicator::network(ind.network).to_string());
            ind_network.set_visible(true);
            if matches!(ind.network, sysstate::Network::Off) {
                ind_network.add_css_class("off");
            } else {
                ind_network.remove_css_class("off");
            }
            match status::indicator::bluetooth(ind.bluetooth) {
                Some(glyph) => {
                    set_module(&ind_bluetooth, &glyph.to_string());
                    ind_bluetooth.set_visible(true);
                }
                None => ind_bluetooth.set_visible(false),
            }
            ind_dnd.set_visible(ind.dnd);
            ind_recording.set_visible(ind.recording);
            ind_night.set_visible(ind.night);
            ind_awake.set_visible(ind.awake);
        }

        ControlFlow::Continue
    });
}

fn build_window(
    app: &Application,
    width: i32,
    monitor: Option<&gtk::gdk::Monitor>,
) -> ApplicationWindow {
    let window = ApplicationWindow::builder()
        .application(app)
        .title("mangobar")
        .decorated(false)
        .resizable(false)
        .build();

    window.init_layer_shell();
    if let Some(monitor) = monitor {
        window.set_monitor(Some(monitor));
    }
    window.set_namespace(Some("mangobar"));
    window.set_layer(Layer::Top);
    window.set_keyboard_mode(KeyboardMode::None);
    window.set_anchor(
        if BAR_AT_BOTTOM { Edge::Bottom } else { Edge::Top },
        true,
    );
    window.set_anchor(Edge::Left, true);
    window.set_anchor(Edge::Right, true);
    window.set_exclusive_zone(BAR_HEIGHT);
    window.set_default_size(width, BAR_HEIGHT);
    window.set_width_request(width);
    window
}

fn build_root(width: i32) -> gtk::Box {
    let root = gtk::Box::new(Orientation::Horizontal, 0);
    root.set_height_request(BAR_HEIGHT);
    root.set_width_request(width);
    root.set_halign(gtk::Align::Fill);
    root.set_hexpand(true);
    root.add_css_class("bar");
    root.add_css_class("bar-root");
    root
}

fn spawn_status(handle: &Handle, tx: mpsc::Sender<Modules>) {
    let sys_handle = handle.clone();
    handle.spawn(async move {
        let (vol_tx, mut vol_rx) = watch::channel(status::VolumeState::UNKNOWN);
        let (time_tx, mut time_rx) = watch::channel(clock::now());
        let (sys_tx, mut sys_rx) = watch::channel(sysstate::SysState::default());

        clock::spawn(time_tx);
        volume::spawn(vol_tx);
        sysstate::spawn(&sys_handle, sys_tx);

        let build = |volume, time: status::ClockState, sys: &sysstate::SysState| Modules {
            volume: status::VolumeState::module(volume),
            battery: status::battery_module(sys.battery),
            clock: time.module(),
            indicators: sys.indicators,
        };

        let _ = tx.send(build(
            *vol_rx.borrow(),
            *time_rx.borrow(),
            &sys_rx.borrow(),
        ));

        loop {
            tokio::select! {
                changed = vol_rx.changed() => if changed.is_err() { break; },
                changed = time_rx.changed() => if changed.is_err() { break; },
                changed = sys_rx.changed() => if changed.is_err() { break; },
            }

            let volume = newest(&mut vol_rx);
            let time = newest(&mut time_rx);
            let sys = *sys_rx.borrow_and_update();

            if tx.send(build(volume, time, &sys)).is_err() {
                break;
            }
        }
    });
}

fn module_label() -> Label {
    let label = Label::new(None);
    label.add_css_class("module");
    label
}

fn indicator_label() -> Label {
    let label = module_label();
    label.add_css_class("indicator");
    // Hidden until the first poll says otherwise (network un-hides itself).
    label.set_visible(false);
    label
}

fn set_module(label: &Label, text: &str) {
    if label.text() != text {
        label.set_text(text);
    }
}

fn newest<T: Copy>(rx: &mut watch::Receiver<T>) -> T {
    let value = *rx.borrow_and_update();
    while rx.has_changed().unwrap_or(false) {
        rx.borrow_and_update();
    }
    value
}

const FALLBACK_WIDTH: i32 = 1920;

/// Width of the layer surface in the logical pixels GTK lays out in.
///
/// Anchoring left+right is not enough on its own — without a width request GTK
/// shrinks the bar to its natural width instead of spanning the output. mango's
/// own `width` is already logical, so it is used as-is; gdk's `Monitor::geometry()`
/// is in device pixels and its `scale()` accessor is feature-gated in gdk4 0.11,
/// which makes the compositor the better source here.
fn logical_width(output: Option<&str>) -> i32 {
    mmsg::monitors()
        .ok()
        .and_then(|all| mmsg::select(&all, output).map(mmsg::MonitorState::logical_width))
        .filter(|width| *width > 0)
        .unwrap_or(FALLBACK_WIDTH)
}

/// The GDK monitor whose connector matches `--output` (e.g. "eDP-1"), or the
/// first one when no name was given.
fn gdk_monitor(name: Option<&str>) -> Option<gtk::gdk::Monitor> {
    let monitors = gtk::gdk::Display::default()?.monitors();
    let found = (0..monitors.n_items())
        .filter_map(|index| monitors.item(index).and_downcast::<gtk::gdk::Monitor>());

    match name {
        Some(name) => {
            let mut found = found;
            found.find(|monitor| monitor.connector().as_deref() == Some(name))
        }
        None => {
            let mut found = found;
            found.next()
        }
    }
}

fn install_css() -> CssProvider {
    let provider = CssProvider::new();
    provider.connect_parsing_error(|_, section, error| {
        eprintln!("mangobar: css: {}: {error}", section.to_str());
    });
    theme::load(&provider);

    if let Some(display) = gtk::gdk::Display::default() {
        // Above PRIORITY_USER, not PRIORITY_APPLICATION. ~/.config/gtk-4.0/gtk.css
        // is a full desktop theme (Orchis) loaded at user priority, and its
        // `.text-button { border-radius: 999px }` turned every tag into a pill
        // on a compositor that runs border_radius=0 everywhere else.
        gtk::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_USER + 1,
        );
    }
    provider
}

fn render_tags(tags_box: &gtk::Box, last_tags: &Rc<RefCell<Vec<Tag>>>, tags: Vec<Tag>) {
    if *last_tags.borrow() == tags {
        return;
    }

    while let Some(child) = tags_box.first_child() {
        tags_box.remove(&child);
    }

    for tag in &tags {
        if !tag.active && !tag.occupied && !tag.urgent {
            continue;
        }

        let label = Label::new(Some(&tag.number.to_string()));
        label.add_css_class("tag");

        if tag.active {
            label.add_css_class("active");
        } else if tag.occupied {
            label.add_css_class("occupied");
        }
        if tag.urgent {
            label.add_css_class("urgent");
        }

        tags_box.append(&label);
    }

    *last_tags.borrow_mut() = tags;
}

fn load_tags(output: Option<&str>) -> Result<Vec<Tag>, String> {
    let all = mmsg::monitors()?;
    mmsg::select(&all, output)
        .map(|monitor| monitor.tags.clone())
        .ok_or_else(|| match output {
            Some(name) => format!("mmsg reported no monitor named {name}"),
            None => "mmsg reported no monitors".to_string(),
        })
}

fn handle_tray_event(
    event: tray::TrayEvent,
    tray_box: &gtk::Box,
    buttons: &mut HashMap<String, gtk::Button>,
    cmd: &tokio::sync::mpsc::UnboundedSender<tray::TrayCmd>,
) {
    match event {
        tray::TrayEvent::Update(item) => {
            let button = buttons
                .entry(item.key.clone())
                .or_insert_with(|| {
                    let button = tray_button(&item.key, cmd);
                    tray_box.append(&button);
                    button
                });
            button.set_child(Some(&tray_image(&item.icon)));
            button.set_tooltip_text((!item.title.is_empty()).then_some(item.title.as_str()));
            button.set_visible(!item.passive);
        }
        tray::TrayEvent::Remove(key) => {
            if let Some(button) = buttons.remove(&key) {
                tray_box.remove(&button);
            }
        }
        tray::TrayEvent::Menu { key, nodes } => {
            if let Some(button) = buttons.get(&key) {
                show_tray_menu(button, &key, &nodes, cmd);
            }
        }
    }
}

fn tray_button(key: &str, cmd: &tokio::sync::mpsc::UnboundedSender<tray::TrayCmd>) -> gtk::Button {
    let button = gtk::Button::new();
    button.add_css_class("tray-item");

    let (left_key, left_cmd) = (key.to_string(), cmd.clone());
    button.connect_clicked(move |_| {
        let _ = left_cmd.send(tray::TrayCmd::Activate(left_key.clone()));
    });

    let right = gtk::GestureClick::new();
    right.set_button(3);
    let (right_key, right_cmd) = (key.to_string(), cmd.clone());
    right.connect_pressed(move |_, _, _, _| {
        let _ = right_cmd.send(tray::TrayCmd::OpenMenu(right_key.clone()));
    });
    button.add_controller(right);
    button
}

fn tray_image(icon: &tray::Icon) -> gtk::Image {
    let image = match icon {
        tray::Icon::Name { name, .. } if name.starts_with('/') => gtk::Image::from_file(name),
        tray::Icon::Name { name, theme_path } => {
            // Some apps ship their icon in a private directory and only give
            // its name; teach the display's icon theme about that directory.
            if !theme_path.is_empty() {
                if let Some(display) = gtk::gdk::Display::default() {
                    let theme = gtk::IconTheme::for_display(&display);
                    let known = theme
                        .search_path()
                        .iter()
                        .any(|dir| dir == std::path::Path::new(theme_path));
                    if !known {
                        theme.add_search_path(theme_path);
                    }
                }
            }
            gtk::Image::from_icon_name(name)
        }
        tray::Icon::Pixmap { width, height, rgba } => {
            let bytes = glib::Bytes::from(rgba);
            let texture = gtk::gdk::MemoryTexture::new(
                *width,
                *height,
                gtk::gdk::MemoryFormat::R8g8b8a8,
                &bytes,
                (*width * 4) as usize,
            );
            gtk::Image::from_paintable(Some(&texture))
        }
        tray::Icon::None => gtk::Image::from_icon_name("application-x-executable"),
    };
    image.set_pixel_size(TRAY_ICON_SIZE);
    image
}

fn show_tray_menu(
    button: &gtk::Button,
    key: &str,
    nodes: &[tray::MenuNode],
    cmd: &tokio::sync::mpsc::UnboundedSender<tray::TrayCmd>,
) {
    let actions = gio::SimpleActionGroup::new();
    let menu = gio::Menu::new();
    build_tray_menu(&menu, nodes, &actions, key, cmd);
    button.insert_action_group("tray", Some(&actions));

    let popover = gtk::PopoverMenu::from_model(Some(&menu));
    popover.set_has_arrow(false);
    popover.set_parent(button);
    // Unparent after the close animation, or the next menu stacks on top.
    popover.connect_closed(|popover| {
        let popover = popover.clone();
        glib::idle_add_local_once(move || popover.unparent());
    });
    popover.popup();
}

/// dbusmenu → GMenu. Separators start a new section; submenus recurse.
fn build_tray_menu(
    menu: &gio::Menu,
    nodes: &[tray::MenuNode],
    actions: &gio::SimpleActionGroup,
    key: &str,
    cmd: &tokio::sync::mpsc::UnboundedSender<tray::TrayCmd>,
) {
    let mut section = gio::Menu::new();
    for node in nodes.iter().filter(|node| node.visible) {
        if node.separator {
            if section.n_items() > 0 {
                menu.append_section(None, &section);
                section = gio::Menu::new();
            }
            continue;
        }

        let label = match node.checked {
            Some(true) => format!("\u{2713} {}", node.label),
            _ => node.label.clone(),
        };

        if !node.children.is_empty() {
            let submenu = gio::Menu::new();
            build_tray_menu(&submenu, &node.children, actions, key, cmd);
            section.append_submenu(Some(&label), &submenu);
            continue;
        }

        let name = format!("m{}", node.id).replace('-', "n");
        let action = gio::SimpleAction::new(&name, None);
        action.set_enabled(node.enabled);
        let (key, cmd, id) = (key.to_string(), cmd.clone(), node.id);
        action.connect_activate(move |_, _| {
            let _ = cmd.send(tray::TrayCmd::MenuClicked { key: key.clone(), id });
        });
        actions.add_action(&action);
        section.append(Some(&label), Some(&format!("tray.{name}")));
    }
    if section.n_items() > 0 {
        menu.append_section(None, &section);
    }
}
