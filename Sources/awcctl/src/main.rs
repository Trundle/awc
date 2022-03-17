use std::env;
use std::io::{Read, Write};
use std::os::unix::net::UnixStream;

use serde::de::DeserializeOwned;
use serde::Serialize;

#[derive(Serialize)]
#[serde(rename_all = "snake_case", tag = "cmd")]
enum Request {
    ListLayouts {},
    SetLayout { layout_number: u8 },
}

fn get_arg_matches() -> clap::ArgMatches {
    clap::Command::new("awcctl")
        .arg(
            clap::Arg::new("menu")
                .long("menu")
                .default_value("whisker-menu"),
        )
        .subcommand(clap::Command::new("list-layouts"))
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
    stream.write_all(&serialized.as_bytes())?;

    Ok(())
}

fn read_response<R: DeserializeOwned>(
    stream: &mut UnixStream,
) -> Result<R, Box<dyn std::error::Error>> {
    let response_size = read_size(stream)? as usize;
    let mut response_data = vec![0; response_size];
    stream.read_exact(response_data.as_mut_slice())?;

    serde_json::from_slice(&response_data.as_slice()).map_err(|x| x.into())
}

fn request_layouts(stream: &mut UnixStream) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    send_request(stream, &Request::ListLayouts {})?;
    read_response(stream)
}

fn list_layouts(stream: &mut UnixStream) -> Result<(), Box<dyn std::error::Error>> {
    let response = request_layouts(stream)?;
    println!("{}", response.join("\n"));

    Ok(())
}

fn select_layout(stream: &mut UnixStream, menu: &str) -> Result<(), Box<dyn std::error::Error>> {
    let layouts = request_layouts(stream)?;
    if let Some(layout_number) = exec_menu(menu, &layouts.as_slice())? {
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

    let socket_path = env::var("AWCSOCK")?;
    let mut socket = UnixStream::connect(socket_path)?;

    match args.subcommand() {
        Some(("list-layouts", _)) => list_layouts(&mut socket)?,
        Some(("select-layout", _)) => select_layout(&mut socket, args.value_of("menu").unwrap())?,
        _ => {}
    }

    Ok(())
}
