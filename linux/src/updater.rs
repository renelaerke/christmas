//! Self-update from GitHub releases, as `src/Updater.cs`. The release workflow builds the Linux binary with the
//! release tag as its version and attaches `JuleHygge-linux-x86_64.tar.gz` to the release. The app asks the GitHub
//! API for the latest release, downloads a newer tarball, checks it, takes the binary out next to itself, and
//! renames it over the running one (Linux allows that: the running process keeps its old file). Local builds have
//! version 0.0.0 and never update themselves.
//!
//! Test aids (as on macOS): `JULE_UPDATE_TARBALL=file.tar.gz` with `JULE_UPDATE_TARBALL_VERSION=x.y.z` stands in for
//! GitHub's latest release, so the whole update can be tried on a copy; `--update-test=github` asks GitHub and
//! checks what it would install, without installing.
//!
//! The downloaded binary is never run to learn its version: like the .NET metadata Windows reads, every build
//! carries a version marker (`VERSION_MARKER`) that is read straight from the file.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::Duration;

use sha2::Digest;

/// The project's releases (upstream).
pub const REPO: &str = "rkl1976/christmas";
pub const ASSET: &str = "JuleHygge-linux-x86_64.tar.gz";
/// Tells the supervisor to start the new binary and step down.
pub const RESTART_EXIT_CODE: i32 = 3;

/// The version, readable from the file without running it (see `version_in_file`).
#[used]
static VERSION_MARKER: &[u8] = concat!("\0JULEHYGGE-VERSION=", env!("APP_VERSION"), "\0").as_bytes();
const MARKER_PREFIX: &[u8] = b"\0JULEHYGGE-VERSION=";

static EXE: OnceLock<PathBuf> = OnceLock::new();

/// The binary's path at start; captured once, because an update renames another file over it.
pub fn exe_path() -> PathBuf {
    EXE.get_or_init(|| std::env::current_exe().unwrap_or_else(|_| PathBuf::from("JuleHygge"))).clone()
}

pub type Version = (u32, u32, u32);

pub fn parse_version(s: &str) -> Option<Version> {
    let s = s.trim().trim_start_matches(['v', 'V']);
    let mut it = s.split('.').map(|p| p.parse::<u32>().ok());
    let v = (it.next()??, it.next()??, it.next()??);
    it.next().is_none().then_some(v)
}

pub fn display((a, b, c): Version) -> String {
    format!("{a}.{b}.{c}")
}

/// The stamped version. `JULE_UPDATE_VERSION=x.y.z` pretends to be another version (testing).
pub fn current() -> Version {
    std::env::var("JULE_UPDATE_VERSION")
        .ok()
        .and_then(|v| parse_version(&v))
        .or_else(|| parse_version(crate::VERSION))
        .unwrap_or((0, 0, 0))
}

pub fn is_release_build() -> bool {
    current() > (0, 0, 0)
}

pub enum Outcome {
    UpToDate,
    /// A newer release, downloaded and checked; `install` puts it in place.
    Ready {
        version: Version,
        file: PathBuf,
    },
    Failed(String),
}

fn dir() -> PathBuf {
    exe_path().parent().map(Path::to_path_buf).unwrap_or_else(|| PathBuf::from("."))
}

/// Finds the latest release and, if it is newer and has the Linux tarball, downloads and checks it. Runs on a
/// worker thread.
pub fn check_and_download() -> Outcome {
    match check(&dir()) {
        Ok(o) => o,
        Err(e) => Outcome::Failed(e),
    }
}

fn check(dir: &Path) -> Result<Outcome, String> {
    // a leftover from an update that was not installed
    let new_path = dir.join("JuleHygge.new");
    let _ = std::fs::remove_file(&new_path);

    let (remote, tag, data) = match local_release()? {
        Some(r) => r,
        None => match from_github()? {
            Some(r) => r,
            None => return Ok(Outcome::UpToDate),
        },
    };
    if remote <= current() {
        return Ok(Outcome::UpToDate);
    }
    let bin = binary_from_tarball(&data)?;
    match version_in_file(&bin) {
        Some(v) if v == remote => {}
        Some(v) => return Err(format!("downloaded binary has version {}, expected {}", display(v), display(remote))),
        None => return Err("downloaded file is not JuleHygge".into()),
    }
    write_executable(&new_path, &bin)?;
    crate::log::debug(&format!("update: downloaded {tag}"));
    Ok(Outcome::Ready { version: remote, file: new_path })
}

/// `JULE_UPDATE_TARBALL` and `JULE_UPDATE_TARBALL_VERSION`: a local tarball in place of GitHub's latest release.
fn local_release() -> Result<Option<(Version, String, Vec<u8>)>, String> {
    let Some(path) = std::env::var_os("JULE_UPDATE_TARBALL") else { return Ok(None) };
    let v = std::env::var("JULE_UPDATE_TARBALL_VERSION").unwrap_or_default();
    let version =
        parse_version(&v).ok_or_else(|| format!("JULE_UPDATE_TARBALL_VERSION must look like 1.2.3, got '{v}'"))?;
    let data = std::fs::read(&path).map_err(|e| format!("{}: {e}", PathBuf::from(&path).display()))?;
    Ok(Some((version, format!("v{v} (local)"), data)))
}

/// The latest release from GitHub: its version, tag and the downloaded tarball (checked against its digest), or
/// None when there is nothing newer or the release has no Linux tarball yet.
fn from_github() -> Result<Option<(Version, String, Vec<u8>)>, String> {
    let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(120)).user_agent("JuleHygge-Updater").build();
    let url = format!("https://api.github.com/repos/{REPO}/releases/latest");
    let resp = agent.get(&url).set("Accept", "application/vnd.github+json").call().map_err(|e| e.to_string())?;
    let root: serde_json::Value = serde_json::from_reader(resp.into_reader()).map_err(|e| e.to_string())?;
    let tag = root["tag_name"].as_str().unwrap_or_default().to_string();
    let remote = parse_version(&tag).ok_or_else(|| format!("unreadable release tag: {tag}"))?;
    if remote <= current() {
        return Ok(None);
    }
    let asset = root["assets"].as_array().and_then(|a| a.iter().find(|a| a["name"].as_str() == Some(ASSET)));
    // The tarball is attached by the workflow a few minutes after the release is published; try again later.
    let Some(asset) = asset else {
        crate::log::debug(&format!("update: {tag} has no {ASSET} yet"));
        return Ok(None);
    };
    let link = asset["browser_download_url"].as_str().ok_or("release asset without a download link")?;
    let digest = asset["digest"].as_str().map(str::to_string);
    let resp = agent.get(link).set("Accept", "application/octet-stream").call().map_err(|e| e.to_string())?;
    let mut data = Vec::new();
    resp.into_reader().take(200 << 20).read_to_end(&mut data).map_err(|e| e.to_string())?;
    if let Some(d) = digest.as_deref().and_then(|d| d.strip_prefix("sha256:")) {
        let hash: String = sha2::Sha256::digest(&data).iter().map(|b| format!("{b:02x}")).collect();
        if !hash.eq_ignore_ascii_case(d) {
            return Err("downloaded file does not match its SHA-256 digest".into());
        }
    }
    crate::log::debug(&format!("update: {tag} downloaded ({} bytes)", data.len()));
    Ok(Some((remote, tag, data)))
}

/// `--update-test=github`: what an update would do now, without installing it. Prints the outcome.
pub fn test_against_github() -> Outcome {
    let o = check_and_download();
    if let Outcome::Ready { file, .. } = &o {
        let _ = std::fs::remove_file(file);
    }
    o
}

/// The `JuleHygge` binary from the release tarball (`JuleHygge`, `install.sh`, `README.md`).
fn binary_from_tarball(gz: &[u8]) -> Result<Vec<u8>, String> {
    let mut archive = tar::Archive::new(flate2::read::GzDecoder::new(gz));
    for entry in archive.entries().map_err(|e| e.to_string())? {
        let mut entry = entry.map_err(|e| e.to_string())?;
        let is_bin = entry.path().ok().and_then(|p| p.file_name().map(|n| n == "JuleHygge")).unwrap_or(false);
        if is_bin && entry.header().entry_type().is_file() {
            let mut out = Vec::new();
            entry.read_to_end(&mut out).map_err(|e| e.to_string())?;
            return Ok(out);
        }
    }
    Err(format!("{ASSET} has no JuleHygge binary"))
}

/// The version marker in a JuleHygge binary, if it is one.
pub fn version_in_file(bin: &[u8]) -> Option<Version> {
    let mut from = 0;
    while let Some(i) = find(&bin[from..], MARKER_PREFIX) {
        let start = from + i + MARKER_PREFIX.len();
        let rest = &bin[start..bin.len().min(start + 32)];
        if let Some(end) = rest.iter().position(|b| *b == 0) {
            if let Some(v) = std::str::from_utf8(&rest[..end]).ok().and_then(parse_version) {
                return Some(v);
            }
        }
        from = start;
    }
    None
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    hay.windows(needle.len()).position(|w| w == needle)
}

fn write_executable(path: &Path, data: &[u8]) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::write(path, data).map_err(|e| format!("cannot write {}: {e}", path.display()))?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).map_err(|e| e.to_string())
}

/// Puts the downloaded binary in place of the running one.
pub fn install(file: &Path) -> Result<(), String> {
    let exe = exe_path();
    std::fs::rename(file, &exe).map_err(|e| format!("cannot replace {}: {e}", exe.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn versions() {
        assert_eq!(parse_version("v1.5.1"), Some((1, 5, 1)));
        assert_eq!(parse_version("1.10.0"), Some((1, 10, 0)));
        assert_eq!(parse_version("1.5"), None);
        assert_eq!(parse_version("v1.5.1-rc1"), None);
        assert!(parse_version("1.10.0") > parse_version("1.9.9"));
    }

    #[test]
    fn the_version_can_be_read_from_a_binary() {
        // this test binary carries the marker too
        let me = std::fs::read(std::env::current_exe().unwrap()).unwrap();
        assert_eq!(version_in_file(&me), parse_version(crate::VERSION));
        assert_eq!(version_in_file(b"no marker here"), None);
        let fake = [b"xx".as_slice(), MARKER_PREFIX, b"2.3.4\0yy"].concat();
        assert_eq!(version_in_file(&fake), Some((2, 3, 4)));
    }

    #[test]
    fn tarball_with_the_binary() {
        let mut tar = tar::Builder::new(Vec::new());
        for (name, body) in [("README.md", b"readme".as_slice()), ("JuleHygge", b"\x7fELF binary".as_slice())] {
            let mut h = tar::Header::new_gnu();
            h.set_size(body.len() as u64);
            h.set_mode(0o755);
            h.set_cksum();
            tar.append_data(&mut h, name, body).unwrap();
        }
        let raw = tar.into_inner().unwrap();
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::fast());
        std::io::Write::write_all(&mut gz, &raw).unwrap();
        let gz = gz.finish().unwrap();
        assert_eq!(binary_from_tarball(&gz).unwrap(), b"\x7fELF binary");
    }
}
