//! Fork patch (AzureDominus/agent-browser, see PATCHED.md): do not send CDP
//! `Runtime.enable` to pages unless `AGENT_BROWSER_CAPTURE_CONSOLE=1`.
//!
//! Pages can observe `Runtime.enable` (the "Runtime.enable leak" bot
//! detectors check). agent-browser only needs the Runtime domain's events for
//! `console`/`errors` capture (`Runtime.consoleAPICalled`,
//! `Runtime.exceptionThrown`); `Runtime.evaluate`, `callFunctionOn` and
//! `addBinding` work without it. The variable is read by the daemon, so it
//! must be set when the daemon starts.

pub(crate) const CAPTURE_CONSOLE_ENV: &str = "AGENT_BROWSER_CAPTURE_CONSOLE";

/// Whether page sessions should get `Runtime.enable`.
pub(crate) fn runtime_enable_wanted() -> bool {
    is_truthy(std::env::var(CAPTURE_CONSOLE_ENV).ok().as_deref())
}

fn is_truthy(value: Option<&str>) -> bool {
    matches!(
        value.map(str::to_ascii_lowercase).as_deref(),
        Some("1" | "true" | "yes")
    )
}

#[cfg(test)]
mod tests {
    use super::is_truthy;

    #[test]
    fn test_capture_console_is_opt_in() {
        assert!(!is_truthy(None));
        for off in ["", "0", "false", "no", "off"] {
            assert!(!is_truthy(Some(off)), "{off}");
        }
        for on in ["1", "true", "TRUE", "yes"] {
            assert!(is_truthy(Some(on)), "{on}");
        }
    }
}
