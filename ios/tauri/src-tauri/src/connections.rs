use crate::client::normalize_server;

const HISTORY_LIMIT: usize = 10;

#[derive(Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryEntry {
    pub server: String,
    #[serde(default)]
    pub allow_insecure_http: bool,
}

#[derive(Default, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConnectionInfo {
    pub server: Option<String>,
    #[serde(default)]
    pub allow_insecure_http: bool,
    // None identifies pre-history settings. An explicitly empty list stays empty.
    #[serde(default)]
    pub history: Option<Vec<HistoryEntry>>,
}

impl ConnectionInfo {
    pub fn sanitized(mut self) -> Self {
        let selected = self.server.as_deref().and_then(|value| normalize_server(value, self.allow_insecure_http).ok());
        self.server = selected.as_ref().map(|url| url.as_str().into());
        self.allow_insecure_http = selected.is_some_and(|url| url.scheme() == "http") && self.allow_insecure_http;
        let old_history = self.history.take().unwrap_or_else(|| self.server.as_ref().map(|server| vec![HistoryEntry {
            server: server.clone(), allow_insecure_http: self.allow_insecure_http,
        }]).unwrap_or_default());
        let mut history: Vec<HistoryEntry> = Vec::new();
        for entry in old_history {
            if let Ok(url) = normalize_server(&entry.server, entry.allow_insecure_http) {
                if history.len() < HISTORY_LIMIT && !history.iter().any(|saved| saved.server == url.as_str()) {
                    history.push(HistoryEntry { server: url.as_str().into(), allow_insecure_http: url.scheme() == "http" && entry.allow_insecure_http });
                }
            }
        }
        self.history = Some(history);
        self
    }

    pub fn remember(&mut self, server: &tauri::Url, allow_insecure_http: bool) {
        self.server = Some(server.as_str().into());
        self.allow_insecure_http = server.scheme() == "http" && allow_insecure_http;
        self.forget(server.as_str());
        let history = self.history.as_mut().unwrap();
        history.insert(0, HistoryEntry { server: server.as_str().into(), allow_insecure_http: self.allow_insecure_http });
        history.truncate(HISTORY_LIMIT);
    }

    pub fn forget(&mut self, server: &str) {
        self.history.get_or_insert_with(Vec::new).retain(|entry| entry.server != server);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrates_saved_servers_but_does_not_restore_removed_entries() {
        let mut info: ConnectionInfo = serde_json::from_str(r#"{"server":"https://EXAMPLE.com"}"#).unwrap();
        info = info.sanitized();
        assert_eq!(info.history.as_ref().unwrap()[0].server, "https://example.com/");
        info.forget("https://example.com/");
        let reloaded: ConnectionInfo = serde_json::from_slice(&serde_json::to_vec(&info).unwrap()).unwrap();
        assert!(reloaded.sanitized().history.unwrap().is_empty());
        assert_eq!(info.server.as_deref(), Some("https://example.com/"));
    }

    #[test]
    fn remembers_recent_distinct_origins_and_their_http_consent() {
        let mut info = ConnectionInfo::default().sanitized();
        for index in 0..12 {
            info.remember(&normalize_server(&format!("https://server{index}.example"), false).unwrap(), false);
        }
        info.remember(&normalize_server("https://server10.example:443", false).unwrap(), false);
        assert_eq!(info.history.as_ref().unwrap().len(), 10);
        assert_eq!(info.history.as_ref().unwrap()[0].server, "https://server10.example/");
        info.remember(&normalize_server("http://lan.local:8000", true).unwrap(), true);
        let reloaded: ConnectionInfo = serde_json::from_slice(&serde_json::to_vec(&info).unwrap()).unwrap();
        let reloaded = reloaded.sanitized();
        assert!(reloaded.history.as_ref().unwrap()[0].allow_insecure_http);
        assert!(!reloaded.history.as_ref().unwrap()[1].allow_insecure_http);
    }

    #[test]
    fn rejects_unsafe_history_without_losing_valid_entries() {
        let info: ConnectionInfo = serde_json::from_str(r#"{"server":null,"history":[{"server":"https://user:secret@example.com"},{"server":"http://lan.local"},{"server":"https://EXAMPLE.com:443"},{"server":"https://example.com/"},{"server":"https://example.com:8443"}]}"#).unwrap();
        let info = info.sanitized();
        let servers: Vec<_> = info.history.unwrap().into_iter().map(|entry| entry.server).collect();
        assert_eq!(servers, ["https://example.com/", "https://example.com:8443/"]);
    }
}
