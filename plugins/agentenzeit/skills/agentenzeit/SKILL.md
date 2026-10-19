---
name: agentenzeit
description: Regeln für die Agentenzeit von let's automate. Gilt, sobald im Kontext ein Hinweis «Agentenzeit:» steht oder der Mensch nach Agentenzeit, /aufgabe oder dem Melden von Laufzeit fragt.
---

# Agentenzeit melden

Das Plugin misst auf diesem Rechner, wie lange Du als Agent aktiv gearbeitet hast. Gezählt wird von der Eingabe des Menschen bis zu Deiner Antwort. Lesezeit, Rückfragen und Freigabe-Dialoge zählen nicht. Die Zeit wird über das MCP-Werkzeug `invoicing_agent_time_log` (LaInvoicing über McpConnect) auf eine Aufgabe, ein Projekt oder ein Ticket gemeldet.

## Regeln

1. **Nie schätzen.** Melde nur, was ein Hinweis «Agentenzeit – Bitte melden» vorgibt: `seconds`, `ref`, `started_at`, `ended_at` und den Gegenstand unverändert übernehmen. Selbst ausgedachte Zeiten sind verboten.
2. **Sofort melden.** Steht der Hinweis im Kontext, ist der Aufruf das Erste in Deiner Antwort, noch vor der eigentlichen Anfrage. In `description` gehört eine kurze Zeile, woran Du gearbeitet hast, sachlich und ohne Kundengeheimnisse.
3. **Kurz bestätigen,** in einer Zeile: z. B. «12 min Agentenzeit auf A123 gemeldet». Antwortet der Server mit `logged_only`, sag: «nur protokolliert, Agentenzeit ist auf A123 nicht freigegeben».
4. **Bei einem Fehler** (Werkzeug fehlt, keine Leistung eingestellt, Aufgabe unbekannt) einmal kurz Bescheid geben und nicht wiederholen. Das Plugin bietet die Zeit später erneut an, mit derselben Referenz, und der Server bucht sie nur einmal.
5. **Die Aufgabe bestimmt der Mensch,** mit `/aufgabe A123` (Aufgabe), `P12` (Projekt), `T4711` (Ticket) oder `/aufgabe keine`. Wechsle die Aufgabe nie selbst. Arbeitest Du erkennbar für einen anderen Kunden als die gesetzte Aufgabe, frag nach.

## Was der Server tut

- Ob Agentenzeit verrechnet wird, entscheidet der Schalter «Agentenzeit verrechnen» am Projekt oder an der Aufgabe. Ab Werk steht er auf nein, Tickets verrechnen nie. Ohne Freigabe wird die Zeit nur protokolliert.
- Je Person, Gegenstand und Tag sammelt ein Zeiteintrag mit dem Kennzeichen «Agent» alle Meldungen. Er erscheint auf der Rechnung, zählt aber nie als Arbeitszeit der Person.
