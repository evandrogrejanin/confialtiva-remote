use hbb_common::config;

// Internal identifier: used unquoted in `sc` commands, service and registry names, so no spaces.
pub const APP_NAME: &str = "ConfialtivaRemote";

// Set at build time from the GitHub repository variables (see confialtiva-windows.yml).
// Empty means the client keeps using the public RustDesk servers.
const RENDEZVOUS_SERVER: Option<&str> = option_env!("CONFIALTIVA_RENDEZVOUS_SERVER");
const RELAY_SERVER: Option<&str> = option_env!("CONFIALTIVA_RELAY_SERVER");
const SERVER_KEY: Option<&str> = option_env!("CONFIALTIVA_SERVER_KEY");

pub fn apply_branding() {
    use base::config::keys;

    *config::APP_NAME.write().unwrap() = APP_NAME.to_owned();

    let mut overwrite = config::OVERWRITE_SETTINGS.write().unwrap();

    // Upstream updates would replace this build with the stock RustDesk client.
    config::OVERWRITE_LOCAL_SETTINGS
        .write()
        .unwrap()
        .insert(keys::OPTION_ENABLE_CHECK_UPDATE.to_owned(), "N".to_owned());
    overwrite.insert(keys::OPTION_ALLOW_AUTO_UPDATE.to_owned(), "N".to_owned());

    // One-time password only: it is rotated as soon as a peer logs in with it, and no
    // permanent password can be set. The person assisted may also accept by click.
    overwrite.insert(
        keys::OPTION_VERIFICATION_METHOD.to_owned(),
        "use-temporary-password".to_owned(),
    );
    overwrite.insert(
        keys::OPTION_TEMPORARY_PASSWORD_LENGTH.to_owned(),
        "8".to_owned(),
    );
    overwrite.insert(keys::OPTION_APPROVE_MODE.to_owned(), "".to_owned());

    if let Some(server) = RENDEZVOUS_SERVER.filter(|s| !s.is_empty()) {
        overwrite.insert(
            keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.to_owned(),
            server.to_owned(),
        );
        let relay = RELAY_SERVER.filter(|s| !s.is_empty()).unwrap_or(server);
        overwrite.insert(keys::OPTION_RELAY_SERVER.to_owned(), relay.to_owned());
        if let Some(key) = SERVER_KEY.filter(|s| !s.is_empty()) {
            overwrite.insert(keys::OPTION_KEY.to_owned(), key.to_owned());
        }
    }
}
