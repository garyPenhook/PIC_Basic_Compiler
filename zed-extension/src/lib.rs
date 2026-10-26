use zed_extension_api::{self as zed, LanguageServerId, Result};

struct BasilExtension;

impl zed::Extension for BasilExtension {
    fn new() -> Self {
        BasilExtension
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &LanguageServerId,
        worktree: &zed::Worktree,
    ) -> Result<zed::Command> {
        // Zed may be started from a launcher without ~/.local/bin on PATH, so fall back to it.
        let command = match worktree.which("basil-lsp") {
            Some(path) => path,
            None => {
                let home = worktree
                    .shell_env()
                    .into_iter()
                    .find(|(k, _)| k == "HOME")
                    .map(|(_, v)| v)
                    .ok_or("basil-lsp not found on PATH and HOME is unset")?;
                format!("{home}/.local/bin/basil-lsp")
            }
        };
        Ok(zed::Command {
            command,
            args: vec![],
            env: worktree.shell_env(),
        })
    }
}

zed::register_extension!(BasilExtension);
