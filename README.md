# let's automate – Claude-Code-Plugins

Interner Plugin-Marktplatz für Claude Code.

| Plugin | Zweck |
|---|---|
| [agentenzeit](plugins/agentenzeit/README.md) | Misst die aktive Laufzeit von Claude Code und meldet sie über McpConnect als Agentenzeit an LaInvoicing |

## Für eine Person

```bash
claude plugin marketplace add letsautomategmbh/claude-plugins
claude plugin install agentenzeit@letsautomate
```

Das Repo ist privat. Die Person braucht Lesezugriff auf GitHub und eine Anmeldung über `gh auth login` und `gh auth setup-git`. Claude Code bringt kein eigenes Token mit.

## Für alle Mitarbeitenden (verwaltete Einstellungen)

Eintrag in den verwalteten Einstellungen. Das geht entweder über claude.ai → Organisation → Claude Code → Managed settings oder als Datei `/Library/Application Support/ClaudeCode/managed-settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "letsautomate": {
      "source": { "source": "github", "repo": "letsautomategmbh/claude-plugins" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "agentenzeit@letsautomate": true
  }
}
```

Aktualisierungen kommen bei Marktplätzen von Dritten nur mit `autoUpdate: true` von selbst. Ein Plugin mit `version` in `plugin.json` wird erst verteilt, wenn diese Fassung steigt.
