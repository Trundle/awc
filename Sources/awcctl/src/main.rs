use std::env;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
#[serde(rename_all = "snake_case", tag = "cmd")]
enum Request {
    ListLayouts {},
    ListWorkspaces {},
    NewWorkspace { tag: String },
    RenameWorkspace { tag: String, new_tag: String },
    SetLayout { layout_number: u8 },
}

#[derive(Debug, Deserialize, Serialize)]
struct ViewBox {
    x: isize,
    y: isize,
    width: isize,
    height: isize,
}

#[derive(Debug, Deserialize, Serialize)]
struct Layout {
    description: String,
    views: Vec<ViewBox>,
}

#[derive(Debug, Deserialize, Serialize)]
struct Workspace {
    tag: String,
    views: Vec<String>,
}

fn get_arg_matches() -> clap::ArgMatches {
    clap::Command::new("awcctl")
        .arg(
            clap::Arg::new("menu")
                .long("menu")
                .default_value("whisker-menu"),
        )
        .arg(
            clap::Arg::new("json")
                .long("json")
                .takes_value(false)
                .help("Output JSON"),
        )
        .subcommand(clap::Command::new("list-layouts"))
        .subcommand(clap::Command::new("list-workspaces"))
        .subcommand(clap::Command::new("new-workspace").arg(clap::Arg::new("tag").required(true)))
        .subcommand(
            clap::Command::new("rename-workspace")
                .arg(clap::Arg::new("tag").required(true))
                .arg(clap::Arg::new("new-tag").required(true)),
        )
        .subcommand(clap::Command::new("select-layout"))
        .subcommand_required(true)
        .get_matches()
}

fn exec_menu(menu: &str, choices: &[String]) -> Result<Option<usize>, Box<dyn std::error::Error>> {
    let mut child = std::process::Command::new(menu)
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(choices.join("\n").as_bytes())?;
    }

    let mut stdout = child.stdout.take().unwrap();
    let mut output = String::new();
    stdout.read_to_string(&mut output)?;
    drop(stdout);
    let trimmed_output = output.trim_end_matches('\n');

    Ok(choices
        .iter()
        .map(|x| x.as_str())
        .position(|x| x == trimmed_output))
}

fn read_size(stream: &mut UnixStream) -> Result<u32, Box<dyn std::error::Error>> {
    let mut size_buf = [0; std::mem::size_of::<u32>()];
    stream.read_exact(&mut size_buf)?;
    Ok(u32::from_ne_bytes(size_buf))
}

fn send_request(
    stream: &mut UnixStream,
    request: &Request,
) -> Result<(), Box<dyn std::error::Error>> {
    let serialized = serde_json::to_string(&request)?;
    let size: u32 = serialized.as_bytes().len() as u32;
    stream.write_all(&size.to_ne_bytes())?;
    stream.write_all(serialized.as_bytes())?;

    Ok(())
}

fn read_response<R: DeserializeOwned>(
    stream: &mut UnixStream,
) -> Result<R, Box<dyn std::error::Error>> {
    let response_size = read_size(stream)? as usize;
    let mut response_data = vec![0; response_size];
    stream.read_exact(response_data.as_mut_slice())?;

    serde_json::from_slice(response_data.as_slice()).map_err(|x| x.into())
}

fn request_layouts(stream: &mut UnixStream) -> Result<Vec<Layout>, Box<dyn std::error::Error>> {
    send_request(stream, &Request::ListLayouts {})?;
    read_response(stream)
}

fn list_layouts(stream: &mut UnixStream, json: bool) -> Result<(), Box<dyn std::error::Error>> {
    let response = request_layouts(stream)?;
    if json {
        println!("{}", serde_json::to_string_pretty(&response)?);
    } else {
        println!(
            "{}",
            response
                .iter()
                .map(|l| l.description.clone())
                .collect::<Vec<String>>()
                .join("\n")
        );
    }

    Ok(())
}

fn list_workspaces(stream: &mut UnixStream, json: bool) -> Result<(), Box<dyn std::error::Error>> {
    send_request(stream, &Request::ListWorkspaces {})?;
    let response: Vec<Workspace> = read_response(stream)?;
    if json {
        println!("{}", serde_json::to_string_pretty(&response)?);
    } else {
        println!(
            "{}",
            response
                .iter()
                .map(|w| format!("{}: {}", w.tag, w.views.join(", ")))
                .collect::<Vec<String>>()
                .join("\n")
        );
    }

    Ok(())
}

fn new_workspace(stream: &mut UnixStream, tag: String) -> Result<(), Box<dyn std::error::Error>> {
    send_request(stream, &Request::NewWorkspace { tag })?;
    let result: String = read_response(stream)?;
    if result == "ok" {
        Ok(())
    } else {
        Err(result.into())
    }
}

fn rename_workspace(
    stream: &mut UnixStream,
    tag: String,
    new_tag: String,
) -> Result<(), Box<dyn std::error::Error>> {
    send_request(stream, &Request::RenameWorkspace { tag, new_tag })?;
    let result: String = read_response(stream)?;
    if result == "ok" {
        Ok(())
    } else {
        Err(result.into())
    }
}

fn select_layout(stream: &mut UnixStream, menu: &str) -> Result<(), Box<dyn std::error::Error>> {
    let layouts = request_layouts(stream)?
        .iter()
        .map(|l| l.description.clone())
        .collect::<Vec<_>>();
    if let Some(layout_number) = exec_menu(menu, layouts.as_slice())? {
        send_request(
            stream,
            &Request::SetLayout {
                layout_number: layout_number as u8,
            },
        )?;
    }

    let result: String = read_response(stream)?;
    if result == "ok" {
        Ok(())
    } else {
        Err(result.into())
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = get_arg_matches();
    let json = args.is_present("json");

    let socket_path = env::var("AWCSOCK")?;
    let mut socket = UnixStream::connect(socket_path)?;

    match args.subcommand() {
        Some(("list-layouts", _)) => list_layouts(&mut socket, json)?,
        Some(("list-workspaces", _)) => list_workspaces(&mut socket, json)?,
        Some(("new-workspace", new_ws_matches)) => {
            new_workspace(&mut socket, new_ws_matches.value_of_t_or_exit("tag"))?
        }
        Some(("rename-workspace", rename_matches)) => rename_workspace(
            &mut socket,
            rename_matches.value_of_t_or_exit("tag"),
            rename_matches.value_of_t_or_exit("new-tag"),
        )?,
        Some(("select-layout", _)) => select_layout(&mut socket, args.value_of("menu").unwrap())?,
        _ => {}
    }

    Ok(())
}
