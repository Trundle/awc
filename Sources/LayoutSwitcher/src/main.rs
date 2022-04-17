use std::{env, path::Path};

use gtk::prelude::*;
use gtk::{glib::Bytes, Application, ApplicationWindow};

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
#[serde(rename_all = "snake_case", tag = "cmd")]
enum Request {
    ListLayouts {},
    SetLayout { layout_number: u8 },
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct ViewBox {
    x: isize,
    y: isize,
    width: isize,
    height: isize,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
struct Layout {
    description: String,
    views: Vec<ViewBox>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let socket_path = env::var("AWCSOCK")?;
    let socket_addr = gio::UnixSocketAddress::new(Path::new(&socket_path));
    let socket_client = gio::SocketClient::new();
    let conn = gio::prelude::SocketClientExt::connect(
        &socket_client,
        &socket_addr,
        Some(&gio::Cancellable::new()),
    )?;
    send_request(&conn.output_stream(), &Request::ListLayouts {})?;
    let layouts: Vec<Layout> = read_response(&conn.input_stream())?;

    let app = Application::builder()
        .application_id("com.github.trundle.awc.layoutswitcher")
        .build();

    app.connect_activate(move |app| {
        let conn = conn.clone();
        let cloned_app = app.clone();
        build_ui(app, &layouts, move |i| {
            for _ in 1..3 {
                let result = send_request(
                    &conn.output_stream(),
                    &Request::SetLayout {
                        layout_number: i as u8,
                    },
                );
                if result.is_ok() {
                    break;
                }
            }
            cloned_app.quit();
        });
    });

    app.run();

    Ok(())
}

fn build_ui<F: 'static>(app: &Application, layouts: &[Layout], callback: F)
where
    F: Fn(i32),
{
    let list_box = gtk::ListBox::builder()
        .activate_on_single_click(true)
        .show_separators(true)
        .build();
    list_box.connect_row_activated(move |_, row| {
        callback(row.index());
    });

    for layout in layouts {
        let layout = layout.clone();
        let hbox = gtk::Box::builder()
            .orientation(gtk::Orientation::Horizontal)
            .homogeneous(false)
            .spacing(24)
            .build();

        let drawing_area = gtk::DrawingArea::new();
        drawing_area.set_content_width(256);
        drawing_area.set_content_height(128);
        drawing_area.set_draw_func(move |_, context, width, height| {
            for (i, view_box) in layout.views.iter().enumerate() {
                let x = 1.0 / ((i + 1) as f64);
                context.set_source_rgb(x, x, x);
                context.rectangle(
                    view_box.x as f64,
                    view_box.y as f64,
                    view_box.width as f64,
                    view_box.height as f64,
                );
                let _ = context.fill();
            }
            context.set_source_rgb(0.0, 0.0, 0.0);
            context.rectangle(0.0, 0.0, width as f64, height as f64);
            let _ = context.stroke();
        });
        hbox.append(&drawing_area);

        let label = gtk::Label::new(Some(&layout.description));
        hbox.append(&label);

        list_box.append(&hbox);
    }

    let scrolled_window = gtk::ScrolledWindow::builder()
        .hscrollbar_policy(gtk::PolicyType::Never)
        .child(&list_box)
        .build();

    let window = ApplicationWindow::builder()
        .application(app)
        .title("Choose layout")
        .child(&scrolled_window)
        .build();

    let event_controller = gtk::EventControllerKey::new();
    event_controller.connect_key_pressed({
        let window = window.clone();

        move |_, key, _, _| {
            if key == gdk::Key::Escape {
                window.close();
            }
            gtk::Inhibit(false)
        }
    });
    window.add_controller(&event_controller);

    window.present();
}

fn send_request(
    stream: &gio::OutputStream,
    request: &Request,
) -> Result<(), Box<dyn std::error::Error>> {
    let serialized = serde_json::to_string(request)?;
    let size: u32 = serialized.as_bytes().len() as u32;
    stream.write_bytes(
        &Bytes::from(&size.to_ne_bytes()),
        Option::<&gio::Cancellable>::None,
    )?;
    stream.write_bytes(
        &Bytes::from(&serialized.as_bytes()),
        Option::<&gio::Cancellable>::None,
    )?;

    Ok(())
}

fn read_response<R: DeserializeOwned>(
    stream: &gio::InputStream,
) -> Result<R, Box<dyn std::error::Error>> {
    let no_cancellable = Option::<&gio::Cancellable>::None;
    let bytes = stream.read_bytes(std::mem::size_of::<u32>(), no_cancellable)?;
    let (_, size_bytes) = bytes.split_at(0);
    let size = u32::from_ne_bytes(size_bytes.try_into().unwrap());

    let bytes = stream.read_bytes(size as usize, no_cancellable)?;
    serde_json::from_slice(&bytes).map_err(|x| x.into())
}
