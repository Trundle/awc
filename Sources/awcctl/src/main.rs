use std::env;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;

use regex::Regex;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
#[serde(rename_all = "snake_case", tag = "cmd")]
enum Request {
    ListLayouts {},
    ListOutputs {},
    ListWorkspaces {},
    NewWorkspace {
        tag: String,
    },
    RenameWorkspace {
        tag: String,
        new_tag: String,
    },
    SetFloating {
        x: i32,
        y: i32,
        width: i32,
        height: i32,
    },
    SetLayout {
        layout_number: u8,
    },
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
struct View {
    title: String,
    focus: bool,
}

#[derive(Debug, Deserialize, Serialize)]
struct Workspace {
    tag: String,
    views: Vec<View>,
}

#[derive(Debug, Deserialize, Serialize)]
struct Output {
    name: String,
    workspace: Workspace,
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
        .subcommand(clap::Command::new("list-outputs"))
        .subcommand(clap::Command::new("list-workspaces"))
        .subcommand(clap::Command::new("new-workspace").arg(clap::Arg::new("tag").required(true)))
        .subcommand(
            clap::Command::new("rename-workspace")
                .arg(clap::Arg::new("tag").required(true))
                .arg(clap::Arg::new("new-tag").required(true)),
        )
        .subcommand(clap::Command::new("select-layout"))
        .subcommand(clap::Command::new("set-floating"))
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

fn request_outputs(stream: &mut UnixStream) -> Result<Vec<Output>, Box<dyn std::error::Error>> {
    send_request(stream, &Request::ListOutputs {})?;
    read_response(stream)
}

fn list_outputs(stream: &mut UnixStream, _: bool) -> Result<(), Box<dyn std::error::Error>> {
    let response = request_outputs(stream)?;
    println!("{}", serde_json::to_string_pretty(&response)?);

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
                .map(|w| format!(
                    "{}: {}",
                    w.tag,
                    w.views
                        .iter()
                        .map(|v| v.title.as_ref())
                        .collect::<Vec<&str>>()
                        .join(", ")
                ))
                .collect::<Vec<String>>()
                .join("\n")
        );
    }

    Ok(())
}

fn read_ok_response(stream: &mut UnixStream) -> Result<(), Box<dyn std::error::Error>> {
    let result: String = read_response(stream)?;
    if result == "ok" {
        Ok(())
    } else {
        Err(result.into())
    }
}

fn new_workspace(stream: &mut UnixStream, tag: String) -> Result<(), Box<dyn std::error::Error>> {
    send_request(stream, &Request::NewWorkspace { tag })?;
    read_ok_response(stream)
}

fn rename_workspace(
    stream: &mut UnixStream,
    tag: String,
    new_tag: String,
) -> Result<(), Box<dyn std::error::Error>> {
    send_request(stream, &Request::RenameWorkspace { tag, new_tag })?;
    read_ok_response(stream)
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

    read_ok_response(stream)
}

fn parse_geometry(line: &str) -> Option<(i32, i32, i32, i32)> {
    let re = Regex::new(r"^(\d+),(\d+) (\d+)x(\d+)\n?$")
        .expect("Should be valid pattern");
    let caps = re.captures(line)?;
    let x: i32 = caps[1].parse().unwrap();
    let y: i32 = caps[2].parse().unwrap();
    let width: i32 = caps[3].parse().unwrap();
    let height: i32 = caps[4].parse().unwrap();
    Some((x, y, width, height))
}

fn set_floating(stream: &mut UnixStream) -> Result<(), Box<dyn std::error::Error>> {
    let mut buffer = String::new();
    let stdin = std::io::stdin();
    stdin.read_line(&mut buffer)?;

    if let Some(geometry) = parse_geometry(&buffer) {
        send_request(
            stream,
            &Request::SetFloating {
                x: geometry.0,
                y: geometry.1,
                width: geometry.2,
                height: geometry.3,
            },
        )?;
        read_ok_response(stream)
    } else {
        Err(format!("Invalid geometry: {buffer}").into())
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = get_arg_matches();
    let json = args.is_present("json");

    let socket_path = env::var("AWCSOCK")?;
    let mut socket = UnixStream::connect(socket_path)?;

    match args.subcommand() {
        Some(("list-layouts", _)) => list_layouts(&mut socket, json)?,
        Some(("list-outputs", _)) => list_outputs(&mut socket, json)?,
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
        Some(("set-floating", _)) => set_floating(&mut socket)?,
        _ => {}
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::parse_geometry;

    #[test]
    fn test_parse_geometry() {
        let result = parse_geometry("0,0 100x200");
        assert_eq!(result, Some((0, 0, 100, 200)));
    }
}
