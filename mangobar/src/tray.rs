// System tray: a StatusNotifierItem host (plus the watcher, when nobody else
// runs one).
//
// Apps such as Telegram, Proton VPN and qBittorrent publish their tray icon as
// a D-Bus object (org.kde.StatusNotifierItem) and announce it to
// org.kde.StatusNotifierWatcher. Nothing else in the light stack owns that name
// — DMS used to — so the first bar to start becomes the watcher; every bar is a
// host that lists the registered items and draws them.
//
// All D-Bus work runs on the bar's tokio runtime. The GTK side only ever sees
// TrayEvent values over a std channel (drained on the UI tick, like the other
// modules) and answers with TrayCmd values.
//
// Menus use com.canonical.dbusmenu, which is what Qt, Electron and
// libappindicator actually implement; the SNI ContextMenu method is mostly
// unimplemented in the wild.

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, mpsc};

use futures_util::StreamExt;
use tokio::runtime::Handle;
use tokio::sync::mpsc as tmpsc;
use tokio::task::JoinHandle;
use zbus::fdo::{DBusProxy, RequestNameFlags, RequestNameReply};
use zbus::message::Header;
use zbus::object_server::SignalEmitter;
use zbus::proxy::CacheProperties;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};
use zbus::{Connection, interface, proxy};

const WATCHER_NAME: &str = "org.kde.StatusNotifierWatcher";
const WATCHER_PATH: &str = "/StatusNotifierWatcher";
const DEFAULT_ITEM_PATH: &str = "/StatusNotifierItem";

#[derive(Clone, Debug, PartialEq)]
pub enum Icon {
    /// A themed icon name, plus the app's private theme directory if it has one.
    Name { name: String, theme_path: String },
    /// Straight-alpha RGBA, already converted from SNI's ARGB32.
    Pixmap { width: i32, height: i32, rgba: Vec<u8> },
    None,
}

#[derive(Clone, Debug, PartialEq)]
pub struct TrayItem {
    pub key: String,
    pub icon: Icon,
    pub title: String,
    /// "Passive" items ask to be hidden.
    pub passive: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct MenuNode {
    pub id: i32,
    pub label: String,
    pub enabled: bool,
    pub visible: bool,
    pub separator: bool,
    /// Some(true/false) for checkmark and radio items.
    pub checked: Option<bool>,
    pub children: Vec<MenuNode>,
}

pub enum TrayEvent {
    Update(TrayItem),
    Remove(String),
    Menu { key: String, nodes: Vec<MenuNode> },
}

pub enum TrayCmd {
    Activate(String),
    OpenMenu(String),
    MenuClicked { key: String, id: i32 },
}

pub fn spawn(handle: &Handle) -> (mpsc::Receiver<TrayEvent>, tmpsc::UnboundedSender<TrayCmd>) {
    let (event_tx, event_rx) = mpsc::channel();
    let (cmd_tx, cmd_rx) = tmpsc::unbounded_channel();
    handle.spawn(async move {
        if let Err(err) = run(event_tx, cmd_rx).await {
            eprintln!("mangobar: tray disabled: {err}");
        }
    });
    (event_rx, cmd_tx)
}

// ── watcher (server side) ──────────────────────────────────────────────────

struct Watcher {
    items: Arc<Mutex<Vec<String>>>,
}

#[interface(name = "org.kde.StatusNotifierWatcher")]
impl Watcher {
    async fn register_status_notifier_item(
        &self,
        service: &str,
        #[zbus(header)] header: Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        // Apps pass either a bus name ("org.kde.StatusNotifierItem-123-1") or
        // just an object path (Electron, libappindicator); in the latter case
        // the item lives on the caller's own connection.
        let sender = header.sender().map(|s| s.to_string()).unwrap_or_default();
        let item = if service.starts_with('/') {
            format!("{sender}{service}")
        } else {
            format!("{service}{DEFAULT_ITEM_PATH}")
        };

        let added = {
            let mut items = self.items.lock().unwrap();
            if items.contains(&item) {
                false
            } else {
                items.push(item.clone());
                true
            }
        };
        if added {
            Self::status_notifier_item_registered(&emitter, &item).await?;
        }
        Ok(())
    }

    async fn register_status_notifier_host(
        &self,
        _service: &str,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> zbus::fdo::Result<()> {
        Self::status_notifier_host_registered(&emitter).await?;
        Ok(())
    }

    #[zbus(property)]
    async fn registered_status_notifier_items(&self) -> Vec<String> {
        self.items.lock().unwrap().clone()
    }

    #[zbus(property)]
    async fn is_status_notifier_host_registered(&self) -> bool {
        true
    }

    #[zbus(property)]
    async fn protocol_version(&self) -> i32 {
        0
    }

    #[zbus(signal)]
    async fn status_notifier_item_registered(
        emitter: &SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_item_unregistered(
        emitter: &SignalEmitter<'_>,
        service: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn status_notifier_host_registered(emitter: &SignalEmitter<'_>) -> zbus::Result<()>;
}

/// Become the watcher unless another bar (or anything else) already is.
async fn try_serve_watcher() -> zbus::Result<Option<Connection>> {
    let items = Arc::new(Mutex::new(Vec::new()));
    let conn = Connection::session().await?;
    conn.object_server()
        .at(WATCHER_PATH, Watcher { items: items.clone() })
        .await?;

    let reply = conn
        .request_name_with_flags(WATCHER_NAME, RequestNameFlags::DoNotQueue.into())
        .await?;
    if reply != RequestNameReply::PrimaryOwner {
        return Ok(None);
    }

    // Drop items whose app went away; apps rarely unregister on exit.
    let watch_conn = conn.clone();
    tokio::spawn(async move {
        let Ok(dbus) = DBusProxy::new(&watch_conn).await else { return };
        let Ok(mut changes) = dbus.receive_name_owner_changed().await else { return };
        while let Some(signal) = changes.next().await {
            let Ok(args) = signal.args() else { continue };
            if args.new_owner().is_some() {
                continue;
            }
            let gone = args.name().to_string();
            let removed: Vec<String> = {
                let mut items = items.lock().unwrap();
                let (dead, alive): (Vec<_>, Vec<_>) = items
                    .drain(..)
                    .partition(|item| split_item(item).0 == gone);
                *items = alive;
                dead
            };
            if removed.is_empty() {
                continue;
            }
            let Ok(iface) = watch_conn
                .object_server()
                .interface::<_, Watcher>(WATCHER_PATH)
                .await
            else {
                continue;
            };
            for item in removed {
                let _ = Watcher::status_notifier_item_unregistered(iface.signal_emitter(), &item)
                    .await;
            }
        }
    });

    Ok(Some(conn))
}

// ── host (client side) ─────────────────────────────────────────────────────

#[proxy(
    interface = "org.kde.StatusNotifierWatcher",
    default_service = "org.kde.StatusNotifierWatcher",
    default_path = "/StatusNotifierWatcher"
)]
trait SniWatcher {
    fn register_status_notifier_host(&self, service: &str) -> zbus::Result<()>;

    #[zbus(property)]
    fn registered_status_notifier_items(&self) -> zbus::Result<Vec<String>>;

    #[zbus(signal)]
    fn status_notifier_item_registered(&self, service: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    fn status_notifier_item_unregistered(&self, service: &str) -> zbus::Result<()>;
}

#[proxy(interface = "org.kde.StatusNotifierItem")]
trait SniItem {
    fn activate(&self, x: i32, y: i32) -> zbus::Result<()>;

    #[zbus(property)]
    fn icon_name(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn icon_pixmap(&self) -> zbus::Result<Vec<(i32, i32, Vec<u8>)>>;

    #[zbus(property)]
    fn icon_theme_path(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn status(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn title(&self) -> zbus::Result<String>;

    #[zbus(property)]
    fn item_is_menu(&self) -> zbus::Result<bool>;

    #[zbus(property)]
    fn menu(&self) -> zbus::Result<OwnedObjectPath>;

    #[zbus(signal)]
    fn new_icon(&self) -> zbus::Result<()>;

    #[zbus(signal)]
    fn new_status(&self, status: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    fn new_title(&self) -> zbus::Result<()>;
}

#[proxy(interface = "com.canonical.dbusmenu")]
trait DBusMenu {
    fn get_layout(
        &self,
        parent_id: i32,
        recursion_depth: i32,
        property_names: &[&str],
    ) -> zbus::Result<(u32, (i32, HashMap<String, OwnedValue>, Vec<OwnedValue>))>;

    fn event(&self, id: i32, event_id: &str, data: &Value<'_>, timestamp: u32)
    -> zbus::Result<()>;

    fn about_to_show(&self, id: i32) -> zbus::Result<bool>;
}

/// "service/path" → ("service", "/path").
fn split_item(item: &str) -> (&str, &str) {
    match item.find('/') {
        Some(at) => (&item[..at], &item[at..]),
        None => (item, DEFAULT_ITEM_PATH),
    }
}

async fn item_proxy(conn: &Connection, key: &str) -> zbus::Result<SniItemProxy<'static>> {
    let (service, path) = split_item(key);
    SniItemProxy::builder(conn)
        .destination(service.to_string())?
        .path(path.to_string())?
        .cache_properties(CacheProperties::No)
        .build()
        .await
}

async fn read_item(proxy: &SniItemProxy<'_>, key: &str) -> TrayItem {
    let name = proxy.icon_name().await.unwrap_or_default();
    let icon = if !name.is_empty() {
        Icon::Name {
            name,
            theme_path: proxy.icon_theme_path().await.unwrap_or_default(),
        }
    } else {
        proxy
            .icon_pixmap()
            .await
            .ok()
            .and_then(|pixmaps| best_pixmap(pixmaps))
            .unwrap_or(Icon::None)
    };

    TrayItem {
        key: key.to_string(),
        icon,
        title: proxy.title().await.unwrap_or_default(),
        passive: proxy.status().await.is_ok_and(|s| s == "Passive"),
    }
}

/// Pick the pixmap closest to a crisp 32px (a 16px logical icon at 2x) and
/// convert SNI's network-order ARGB32 to RGBA.
fn best_pixmap(pixmaps: Vec<(i32, i32, Vec<u8>)>) -> Option<Icon> {
    let (width, height, argb) = pixmaps
        .into_iter()
        .filter(|(w, h, data)| *w > 0 && *h > 0 && data.len() == (*w * *h * 4) as usize)
        .min_by_key(|(w, _, _)| (w - 32).abs())?;
    let rgba = argb
        .chunks_exact(4)
        .flat_map(|px| [px[1], px[2], px[3], px[0]])
        .collect();
    Some(Icon::Pixmap { width, height, rgba })
}

/// Follow one item: send its state now and again on every NewIcon / NewStatus
/// / NewTitle, until the task is aborted.
async fn follow_item(conn: Connection, key: String, tx: mpsc::Sender<TrayEvent>) {
    let Ok(proxy) = item_proxy(&conn, &key).await else { return };
    let mut last = read_item(&proxy, &key).await;
    if tx.send(TrayEvent::Update(last.clone())).is_err() {
        return;
    }

    let (Ok(mut icon), Ok(mut status), Ok(mut title)) = (
        proxy.receive_new_icon().await,
        proxy.receive_new_status().await,
        proxy.receive_new_title().await,
    ) else {
        return;
    };

    loop {
        tokio::select! {
            Some(_) = icon.next() => {}
            Some(_) = status.next() => {}
            Some(_) = title.next() => {}
            else => return,
        }
        let next = read_item(&proxy, &key).await;
        if next != last {
            if tx.send(TrayEvent::Update(next.clone())).is_err() {
                return;
            }
            last = next;
        }
    }
}

async fn run(
    tx: mpsc::Sender<TrayEvent>,
    mut cmds: tmpsc::UnboundedReceiver<TrayCmd>,
) -> zbus::Result<()> {
    // Kept alive for the life of the bar: dropping it releases the name.
    let _watcher = try_serve_watcher().await?;

    let conn = Connection::session().await?;
    let host_name = format!("org.kde.StatusNotifierHost-{}", std::process::id());
    let _ = conn.request_name(host_name.as_str()).await;

    let watcher = SniWatcherProxy::new(&conn).await?;
    watcher.register_status_notifier_host(&host_name).await?;

    let mut registered = watcher.receive_status_notifier_item_registered().await?;
    let mut unregistered = watcher.receive_status_notifier_item_unregistered().await?;

    let mut tasks: HashMap<String, JoinHandle<()>> = HashMap::new();
    let add = |key: String, tasks: &mut HashMap<String, JoinHandle<()>>| {
        if !tasks.contains_key(&key) {
            let task = tokio::spawn(follow_item(conn.clone(), key.clone(), tx.clone()));
            tasks.insert(key, task);
        }
    };

    let initial: HashSet<String> = watcher
        .registered_status_notifier_items()
        .await
        .unwrap_or_default()
        .into_iter()
        .collect();
    for key in initial {
        add(key, &mut tasks);
    }

    loop {
        tokio::select! {
            Some(signal) = registered.next() => {
                if let Ok(args) = signal.args() {
                    add(args.service().to_string(), &mut tasks);
                }
            }
            Some(signal) = unregistered.next() => {
                if let Ok(args) = signal.args() {
                    let key = args.service().to_string();
                    if let Some(task) = tasks.remove(&key) {
                        task.abort();
                    }
                    if tx.send(TrayEvent::Remove(key)).is_err() {
                        return Ok(());
                    }
                }
            }
            Some(cmd) = cmds.recv() => handle_cmd(&conn, cmd, &tx).await,
            else => return Ok(()),
        }
    }
}

async fn handle_cmd(conn: &Connection, cmd: TrayCmd, tx: &mpsc::Sender<TrayEvent>) {
    match cmd {
        TrayCmd::Activate(key) => {
            let Ok(item) = item_proxy(conn, &key).await else { return };
            // Menu-only items (and apps that do not implement Activate) get
            // their menu instead.
            let menu_only = item.item_is_menu().await.unwrap_or(false);
            if menu_only || item.activate(0, 0).await.is_err() {
                open_menu(conn, &key, tx).await;
            }
        }
        TrayCmd::OpenMenu(key) => open_menu(conn, &key, tx).await,
        TrayCmd::MenuClicked { key, id } => {
            if let Ok(menu) = menu_proxy(conn, &key).await {
                let _ = menu.event(id, "clicked", &Value::from(0i32), 0).await;
            }
        }
    }
}

async fn menu_proxy(conn: &Connection, key: &str) -> zbus::Result<DBusMenuProxy<'static>> {
    let item = item_proxy(conn, key).await?;
    let path = item.menu().await?;
    let (service, _) = split_item(key);
    DBusMenuProxy::builder(conn)
        .destination(service.to_string())?
        .path(path)?
        .cache_properties(CacheProperties::No)
        .build()
        .await
}

async fn open_menu(conn: &Connection, key: &str, tx: &mpsc::Sender<TrayEvent>) {
    let Ok(menu) = menu_proxy(conn, key).await else { return };
    let _ = menu.about_to_show(0).await;
    let Ok((_, (_, _, children))) = menu.get_layout(0, -1, &[]).await else { return };
    let nodes = children.iter().filter_map(|child| parse_node(child)).collect();
    let _ = tx.send(TrayEvent::Menu {
        key: key.to_string(),
        nodes,
    });
}

/// One `(ia{sv}av)` layout entry. Children arrive wrapped in variants.
fn parse_node(value: &Value<'_>) -> Option<MenuNode> {
    let value = match value {
        Value::Value(inner) => inner.as_ref(),
        other => other,
    };
    let Value::Structure(structure) = value else { return None };
    let fields = structure.fields();
    let Some(Value::I32(id)) = fields.first() else { return None };

    let mut node = MenuNode {
        id: *id,
        label: String::new(),
        enabled: true,
        visible: true,
        separator: false,
        checked: None,
        children: Vec::new(),
    };

    if let Some(Value::Dict(props)) = fields.get(1) {
        let mut toggle = false;
        let mut state = 0;
        for (key, val) in props.iter() {
            let Value::Str(key) = key else { continue };
            let val = match val {
                Value::Value(inner) => inner.as_ref(),
                other => other,
            };
            match (key.as_str(), val) {
                ("label", Value::Str(s)) => node.label = s.to_string(),
                ("enabled", Value::Bool(b)) => node.enabled = *b,
                ("visible", Value::Bool(b)) => node.visible = *b,
                ("type", Value::Str(s)) => node.separator = s.as_str() == "separator",
                ("toggle-type", Value::Str(s)) => toggle = !s.as_str().is_empty(),
                ("toggle-state", Value::I32(i)) => state = *i,
                _ => {}
            }
        }
        if toggle {
            node.checked = Some(state == 1);
        }
    }

    if let Some(Value::Array(children)) = fields.get(2) {
        node.children = children.iter().filter_map(parse_node).collect();
    }

    Some(node)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_bus_name_and_path() {
        assert_eq!(
            split_item(":1.42/org/ayatana/NotificationItem/x"),
            (":1.42", "/org/ayatana/NotificationItem/x")
        );
        assert_eq!(
            split_item("org.kde.StatusNotifierItem-7-1/StatusNotifierItem"),
            ("org.kde.StatusNotifierItem-7-1", "/StatusNotifierItem")
        );
        assert_eq!(split_item("org.x"), ("org.x", DEFAULT_ITEM_PATH));
    }

    #[test]
    fn pixmap_is_argb_to_rgba_and_nearest_32() {
        let px16 = (16, 16, vec![0u8; 16 * 16 * 4]);
        let px32 = (32, 32, [255u8, 10, 20, 30].repeat(32 * 32));
        let Some(Icon::Pixmap { width, rgba, .. }) = best_pixmap(vec![px16, px32]) else {
            panic!("no pixmap");
        };
        assert_eq!(width, 32);
        assert_eq!(&rgba[..4], &[10, 20, 30, 255]);
    }

    #[test]
    fn malformed_pixmaps_are_skipped() {
        assert_eq!(best_pixmap(vec![(8, 8, vec![0; 3])]), None);
    }
}
