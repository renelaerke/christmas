// Stamps the app version from VERSION=x.y.z (the release workflow passes the release tag).
// Without it the app is 0.0.0: a development build that never updates itself.
fn main() {
    println!("cargo:rerun-if-env-changed=VERSION");
    let v = std::env::var("VERSION").unwrap_or_default();
    let v = if v.is_empty() { "0.0.0".to_string() } else { v };
    let parts: Vec<&str> = v.split('.').collect();
    if parts.len() != 3 || parts.iter().any(|p| p.is_empty() || !p.chars().all(|c| c.is_ascii_digit())) {
        panic!("VERSION must look like 1.2.3, got '{v}'");
    }
    println!("cargo:rustc-env=APP_VERSION={v}");
}
