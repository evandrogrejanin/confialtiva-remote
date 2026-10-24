use hbb_common::config;

// Internal identifier: used unquoted in `sc` commands, service and registry names, so no spaces.
pub const APP_NAME: &str = "ConfialtivaRemote";

pub fn apply_branding() {
    use base::config::keys;

    *config::APP_NAME.write().unwrap() = APP_NAME.to_owned();

    // Upstream updates would replace this build with the stock RustDesk client.
    config::OVERWRITE_LOCAL_SETTINGS
        .write()
        .unwrap()
        .insert(keys::OPTION_ENABLE_CHECK_UPDATE.to_owned(), "N".to_owned());
    config::OVERWRITE_SETTINGS
        .write()
        .unwrap()
        .insert(keys::OPTION_ALLOW_AUTO_UPDATE.to_owned(), "N".to_owned());

    // LGPD: the person being assisted accepts every incoming session by click.
    config::DEFAULT_SETTINGS
        .write()
        .unwrap()
        .insert(keys::OPTION_APPROVE_MODE.to_owned(), "click".to_owned());
}
