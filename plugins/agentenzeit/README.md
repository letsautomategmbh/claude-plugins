# agentenzeit

Misst, wie lange Claude Code auf diesem Rechner aktiv gearbeitet hat. Die Zeit wird über McpConnect als **Agentenzeit** auf eine Aufgabe, ein Projekt oder ein Ticket in LaInvoicing gemeldet.

## So arbeitest Du damit

```
/aufgabe A123      Aufgabe A123
/aufgabe P12       Projekt P12
/aufgabe T4711     Ticket 4711 (wird nur protokolliert, nie verrechnet)
/aufgabe keine     ab jetzt nichts melden
/aufgabe           zeigt die aktuelle Aufgabe
/agentenzeit       zeigt Aufgabe, gemessene und gemeldete Minuten dieser Sitzung
```

Ab einer gesetzten Aufgabe bietet das Plugin dem Agenten die gemessene Zeit zum Melden an, sobald 10 Minuten zusammengekommen sind oder die letzte Meldung über eine Stunde zurückliegt. Der Agent meldet sie mit `invoicing_agent_time_log` und bestätigt das in einer Zeile. Beim Wechsel der Aufgabe wird die offene Zeit zuerst der bisherigen Aufgabe gemeldet. Zeit, die vor dem ersten `/aufgabe` anfiel, geht auf die erste gesetzte Aufgabe.

## Die Leiste über dem Eingabefeld (0.2.0)

Über dem Eingabefeld steht der Stand der Sitzung: `⏱ Agentenzeit: A123 · 12 min offen · 30 min gemeldet`. Die Knöpfe:

- **Aufgabe setzen / wechseln** schreibt `/aufgabe ` ins Eingabefeld; Nummer ergänzen, Enter.
- **Aus** führt `/aufgabe keine` aus.
- **–** blendet die Leiste für diese Sitzung aus; der Stand bleibt in der Statuszeile.

Die Leiste liest nur, was das Messskript je Sitzung ablegt, und frischt sich nach jedem Zug und jede Minute auf. Gemessen und gemeldet wird allein im Skript.

## Was gemessen wird

- **Es zählt nur die aktive Zeit:** von Deiner Eingabe bis zur Antwort des Agenten, einschliesslich laufender Werkzeuge und Unteragenten.
- **Nicht gezählt wird die Zeit, in der ein Mensch gefragt ist:** Lesen, Überlegen, Tippen, Rückfragen (AskUserQuestion, Plan freigeben) und Freigabe-Dialoge.
- **Unteragenten zählen nur einmal,** über die Wartezeit der Hauptsitzung (Entscheid vom 19.10.2026).
- **Grenzen:** höchstens 30 min für eine Lücke vor einer Antwort, 4 h vor einem Werkzeugergebnis und 30 min vor einer Meldung aus dem Hintergrund.

Ob die Zeit verrechnet wird, entscheidet LaInvoicing. Massgebend ist der Schalter «Agentenzeit verrechnen» am Projekt oder an der Aufgabe, ab Werk steht er auf nein. Agentenzeit zählt nie als Arbeitszeit.

## Voraussetzungen

1. **macOS.** Das Skript läuft mit dem Perl des Systems, ohne Xcode-Werkzeuge.
2. **Verbindung zu McpConnect** (support.letsautomate.ch) in Claude Code mit Deinem eigenen FreeScout-Konto. Diesem Zugang muss der Scope **`agenttime:write`** («Agentenzeit melden») erlaubt sein. Zum Prüfen der Aufgabe braucht es zusätzlich `tasks:read`.
3. **In LaInvoicing unter Verwalten → Aktivitäten → Zeiterfassung** ist die «Leistung für Agentenzeit» gesetzt. Ohne sie bucht der Server nichts.

## Installieren

```bash
claude plugin marketplace add letsautomategmbh/claude-plugins
claude plugin install agentenzeit@letsautomate
```

Für alle Mitarbeitenden auf einmal geht das über verwaltete Einstellungen: `extraKnownMarketplaces` und `enabledPlugins`, siehe Repo-README.

## Fehlersuche

- **Zustand je Sitzung** liegt unter `~/.claude/plugins/data/agentenzeit-letsautomate/sitzungen/<sitzung>.json`. Anzeigen lässt er sich mit `perl scripts/agentenzeit.pl status <sitzung>` (vorher `CLAUDE_PLUGIN_DATA` auf den Datenordner setzen).
- **Hook-Eingaben mitschreiben:** Mit `AGENTENZEIT_PROTOKOLL=/pfad/log.txt` in der Umgebung hängt jeder Aufruf seine Eingabe an diese Datei an.
- **Doppelte Meldungen** verhindert der Server. Die Referenz ist Sitzung plus Beginn des Abschnitts, und jede Referenz wird nur einmal gebucht.
