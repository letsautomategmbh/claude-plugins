#!/usr/bin/perl
# agentenzeit -- misst die aktive Laufzeit von Claude Code und bietet sie dem
# Agenten zum Melden an (MCP-Werkzeug invoicing_agent_time_log von
# LaInvoicing, über McpConnect).
#
# Aufrufe (alle lesen das Hook-JSON von STDIN):
#   agentenzeit.pl prompt         UserPromptSubmit: /aufgabe erkennen, messen, anbieten
#   agentenzeit.pl warten         Notification (permission_prompt): Wartezeit merken
#   agentenzeit.pl gemeldet       PostToolUse auf invoicing_agent_time_log: abhaken
#   agentenzeit.pl status <id>    von Hand: Zustand einer Sitzung zeigen
#
# Gemessen wird nur die Hauptsitzung: von einer Eingabe bis zur Antwort. Die
# Zeit, in der der Mensch liest, überlegt oder tippt, zählt nicht, ebenso
# wenig Rückfragen (AskUserQuestion, Plan freigeben) und Freigabe-Dialoge.
# Unteragenten zählen nicht zusätzlich: ihre Laufzeit steckt schon in der
# Wartezeit der Hauptsitzung auf ihr Ergebnis.
#
# Nur Perl mit Kernmodulen -- auf jedem Mac vorhanden, ohne Xcode-Werkzeuge.

use strict;
use utf8;
use warnings;
use JSON::PP;
use File::Path qw(make_path);
use Time::Local qw(timegm);

my $JSON = JSON::PP->new->utf8->canonical;

# Grenzen in Sekunden.
my $DECKEL_ANTWORT  = 30 * 60;      # eine Lücke vor einer Antwort des Modells
my $DECKEL_WERKZEUG = 4 * 3600;     # eine Lücke vor einem Werkzeugergebnis
my $DECKEL_HINTERGRUND = 30 * 60;   # vor einer Meldung eines Hintergrundauftrags
my $SCHWELLE        = 10 * 60;      # ab so viel offener Zeit anbieten
my $SCHWELLE_KLEIN  = 60;           # ... oder ab einer Minute, wenn die letzte Meldung lange her ist
my $LANGE_HER       = 3600;
# Werkzeuge, bei denen die Lücke bis zum Ergebnis ein Mensch füllt.
my %MENSCH_WERKZEUG = map { $_ => 1 } qw(AskUserQuestion ExitPlanMode EnterPlanMode);

my $befehl = shift @ARGV // '';
my $eingabe = '';
if ($befehl ne 'status') {
    local $/;
    $eingabe = <STDIN> // '';
}
my $hook = eval { $JSON->decode($eingabe) } || {};
if ($ENV{AGENTENZEIT_PROTOKOLL} && open my $log, '>>', $ENV{AGENTENZEIT_PROTOKOLL}) {
    print $log scalar(localtime)." $befehl $eingabe\n";
    close $log;
}

if    ($befehl eq 'prompt')   { prompt($hook) }
elsif ($befehl eq 'warten')   { warten($hook) }
elsif ($befehl eq 'gemeldet') { gemeldet($hook) }
elsif ($befehl eq 'status')   { print $JSON->pretty->encode(lade($ARGV[0] // '')) }
exit 0;

# ---------------------------------------------------------------- Zustand

sub ablage {
    my $d = $ENV{CLAUDE_PLUGIN_DATA} || "$ENV{HOME}/.claude/agentenzeit";
    $d .= '/sitzungen';
    make_path($d) unless -d $d;
    return $d;
}

sub datei { my $id = shift; $id =~ s/[^A-Za-z0-9_-]//g; return ablage().'/'.$id.'.json' }

sub lade {
    my $id = shift;
    my $f = datei($id);
    my $z;
    if (open my $fh, '<', $f) { local $/; $z = eval { $JSON->decode(<$fh>) }; close $fh }
    $z ||= { neu => 1 };      # noch nie gesehene Sitzung
    $z->{pos} //= 0;          # gelesene Bytes des Protokolls
    $z->{offen} //= 0;        # gemessene, noch nicht gemeldete Sekunden
    $z->{warten} //= [];      # Zeitpunkte offener Freigabe-Dialoge
    return $z;
}

sub speichere {
    my ($id, $z) = @_;
    my $f = datei($id);
    open my $fh, '>', "$f.tmp" or return;
    print $fh $JSON->encode($z);
    close $fh;
    rename "$f.tmp", $f;
}

sub iso2epoch {
    my $s = shift // return undef;
    return undef unless $s =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.(\d+))?Z$/;
    my $t = timegm($6, $5, $4, $3, $2 - 1, $1);
    return $t + ($7 ? "0.$7" : 0);
}

sub epoch2iso {
    my @t = gmtime(int(shift));
    return sprintf('%04d-%02d-%02dT%02d:%02d:%02dZ', $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0]);
}

# ---------------------------------------------------------------- Messen

# Liest die neuen Zeilen des Protokolls und rechnet die aktiven Sekunden in
# $z->{offen} ein. Ohne JSON-Dekodierung je Zeile: Protokolle werden viele
# Megabyte gross, und der Hook läuft vor jeder Eingabe.
sub messe {
    my ($z, $pfad) = @_;
    return unless $pfad && -f $pfad;
    my $groesse = -s $pfad;
    $z->{pos} = 0 if $z->{pos} > $groesse;    # Protokoll neu (z. B. /clear)
    open my $fh, '<', $pfad or return;
    seek $fh, $z->{pos}, 0;
    my @warten = sort { $a <=> $b } @{ $z->{warten} };
    while (my $zeile = <$fh>) {
        last unless $zeile =~ /\n\z/;   # halbe letzte Zeile: beim nächsten Mal
        $z->{pos} += length $zeile;
        next if $zeile =~ /"isSidechain":true/;
        next unless $zeile =~ /^\{.*?"type":"(user|assistant)"/;
        my $typ = $1;
        my ($ts) = $zeile =~ /"timestamp":"([^"]+)"/;
        my $t = iso2epoch($ts) // next;

        my $art;
        if ($typ eq 'assistant') {
            $art = 'antwort';
        } elsif ($zeile =~ /"type":"tool_result"/) {
            $art = 'ergebnis';
        } elsif ($zeile =~ /"isMeta":true/) {
            next;    # Systemzusatz direkt nach einer Eingabe
        } elsif ($zeile =~ /<task-notification>/) {
            $art = 'hintergrund';
        } else {
            $art = 'mensch';
        }

        if (defined $z->{letzt} && $art ne 'mensch') {
            my $von = $z->{letzt};
            my $luecke = $t - $von;
            if ($luecke > 0 && !$z->{mensch_werkzeug}) {
                my $deckel = $art eq 'antwort' ? $DECKEL_ANTWORT : $art eq 'hintergrund' ? $DECKEL_HINTERGRUND : $DECKEL_WERKZEUG;
                # Ein Freigabe-Dialog in der Lücke: nur bis dorthin zählen.
                for my $w (@warten) {
                    if ($w > $von && $w < $t) { $luecke = $w - $von; last }
                }
                $luecke = $deckel if $luecke > $deckel;
                $z->{offen} += $luecke;
                $z->{offen_von} //= $von;
                $z->{offen_bis} = $t;
            }
        }
        if ($art eq 'antwort') {
            # Wartet die Antwort auf einen Menschen (Rückfrage)? Dann zählt
            # die Lücke bis zum Ergebnis nicht.
            my @namen = $zeile =~ /"type":"tool_use","id":"[^"]*","name":"([^"]+)"/g;
            $z->{mensch_werkzeug} = (grep { $MENSCH_WERKZEUG{$_} } @namen) ? 1 : 0;
        } elsif ($art eq 'ergebnis') {
            $z->{mensch_werkzeug} = 0;
        }
        $z->{letzt} = $t;
    }
    close $fh;
    # Verbrauchte Wartezeitpunkte vergessen.
    $z->{warten} = [ grep { $_ > ($z->{letzt} // 0) } @warten ];
}

# ---------------------------------------------------------------- Hooks

sub prompt {
    my $h = shift;
    my $id = $h->{session_id} // return;
    my $z = lade($id);
    # Eine Sitzung, die das Plugin zum ersten Mal sieht, wird ab jetzt
    # gemessen, nicht ab ihrem Anfang: wer das Plugin mitten in einer langen
    # Sitzung bekommt (Installation, Verteilung ans Team), hätte sonst die
    # ganze Zeit davor auf der ersten Aufgabe (0.1.1, gemessen: 671 min).
    if (delete $z->{neu}) {
        my $p = $h->{transcript_path};
        $z->{pos} = ($p && -f $p) ? (-s $p) : 0;
        $z->{letzt} = time;
    }
    messe($z, $h->{transcript_path});

    my @hinweis;
    my $eingabe = $h->{prompt} // '';

    # /agentenzeit: Stand dieser Sitzung (0.1.2)
    if ($eingabe =~ m{^\s*/(?:agentenzeit:)?agentenzeit\s*$}i) {
        my $aufg = $z->{aufgabe} && $z->{aufgabe} ne 'KEINE' ? $z->{aufgabe} : undef;
        push @hinweis, sprintf('Agentenzeit (nur diese Sitzung): Aufgabe %s; gemessen, noch nicht gemeldet: %d min; in dieser Sitzung gemeldet: %d min. Nenne das dem Menschen in zwei, drei kurzen Zeilen.%s',
            $aufg // (($z->{aufgabe} // '') eq 'KEINE' ? 'keine (Melden ausgeschaltet)' : 'noch keine gesetzt'),
            int(($z->{offen} // 0) / 60 + 0.5), int(($z->{gemeldet_total} // 0) / 60 + 0.5),
            $aufg ? " Falls der Mensch die Summe über alle Sitzungen wissen will: mit invoicing_task_get (bzw. invoicing_project_get) nachsehen, was auf $aufg als Agentenzeit gebucht ist." : '');
    }

    # /aufgabe A123 | P12 | T4711 | keine
    if ($eingabe =~ m{^\s*/(?:agentenzeit:)?aufgabe\b\s*(\S*)}i) {
        my $ziel = uc($1 // '');
        if ($ziel eq '' ) {
            push @hinweis, 'Agentenzeit: Aktuelle Aufgabe ist '.($z->{aufgabe} // 'keine').'. Sag das dem Menschen in einem Satz.';
        } elsif ($ziel =~ /^(KEINE|NONE|AUS|-)$/) {
            push @hinweis, anbieten($z, $id, 1) if $z->{aufgabe};
            $z->{aufgabe} = 'KEINE';
            push @hinweis, 'Agentenzeit: ab jetzt wird keine Agentenzeit gemeldet, bis eine Aufgabe gesetzt wird. Bestätige das in einem Satz.';
        } elsif ($ziel =~ /^(A|P|T|#)?(\d+)$/) {
            my $neu = ($1 && $1 ne '#' ? $1 : 'A').$2;
            # Offene Zeit gehört noch der bisherigen Aufgabe.
            push @hinweis, anbieten($z, $id, 1) if $z->{aufgabe} && $z->{aufgabe} ne 'KEINE' && $z->{aufgabe} ne $neu;
            # War noch keine gesetzt, geht die bisher gemessene Zeit mit auf die neue.
            $z->{aufgabe} = $neu;
            push @hinweis, "Agentenzeit: Aufgabe $neu ist gesetzt. Prüfe mit invoicing_tasks_search/invoicing_task_get (bzw. invoicing_project_get), dass es sie gibt, und nenne dem Menschen in einem Satz Titel, Kunde und ob Agentenzeit dort verrechnet wird.";
        } else {
            push @hinweis, "Agentenzeit: «$ziel» ist keine Aufgabe. Erwartet: /aufgabe A123, P12 (Projekt), T4711 (Ticket) oder /aufgabe keine.";
        }
    }

    if (!@hinweis || $hinweis[0] !~ /Bitte melden/) {
        my $a = anbieten($z, $id, 0);
        push @hinweis, $a if $a;
    }
    # Ohne Aufgabe: einmal je Sitzung erinnern, sobald Zeit zusammenkommt.
    if (!$z->{aufgabe} && $z->{offen} >= $SCHWELLE && !$z->{erinnert}) {
        $z->{erinnert} = 1;
        push @hinweis, sprintf('Agentenzeit: %d min gemessen, aber keine Aufgabe gesetzt. Erwähne am Ende deiner Antwort in einem Satz, dass der Mensch mit /aufgabe A123 die Aufgabe nennen kann (oder /aufgabe keine).', $z->{offen} / 60);
    }
    $z->{aufgabe} = undef if ($z->{aufgabe} // '') eq '' ;

    speichere($id, $z);
    @hinweis = grep { defined && length } @hinweis;
    return unless @hinweis;
    print $JSON->encode({ hookSpecificOutput => { hookEventName => 'UserPromptSubmit', additionalContext => join("\n\n", @hinweis) } });
}

# Bietet die offene Zeit zum Melden an, wenn genug zusammengekommen ist
# (oder $sofort). Die Referenz hängt am Beginn des Abschnitts: wird dieselbe
# Zeit nochmals angeboten (weil die Meldung ausblieb), bleibt sie gleich,
# und der Server bucht sie nur einmal.
sub anbieten {
    my ($z, $id, $sofort) = @_;
    my $aufgabe = $z->{aufgabe} // return '';
    if ($aufgabe eq 'KEINE') {
        # Verfällt: weder gemeldet noch später einer Aufgabe zugeschlagen.
        verbuche($z, $z->{offen}, $z->{offen_bis});
        return '';
    }
    my $sek = int($z->{offen});
    return '' if $sek < $SCHWELLE_KLEIN;
    my $her = time - ($z->{zuletzt_angeboten} // 0);
    return '' unless $sofort || $sek >= $SCHWELLE || $her >= $LANGE_HER;

    my $von = $z->{offen_von} // $z->{letzt};
    my $ref = substr($id, 0, 64).':'.int($von);
    $z->{angebot} = { ref => $ref, aufgabe => $aufgabe, sekunden => $sek, bis => $z->{offen_bis} };
    $z->{zuletzt_angeboten} = time;
    my $feld = $aufgabe =~ /^P(\d+)/ ? qq("project": "$aufgabe") : $aufgabe =~ /^T(\d+)/ ? qq("conversation_id": $1) : qq("task": "$aufgabe");
    return sprintf(
        "Agentenzeit – Bitte melden: Rufe jetzt, vor allem anderen, das MCP-Werkzeug invoicing_agent_time_log auf, genau mit {%s, \"seconds\": %d, \"ref\": \"%s\", \"started_at\": \"%s\", \"ended_at\": \"%s\", \"description\": <eine kurze Zeile, woran du seit %s gearbeitet hast>}. Werte nicht ändern, nichts schätzen. Danach eine kurze Zeile an den Menschen (z. B. «%d min Agentenzeit auf %s gemeldet»), dann weiter mit seiner Anfrage. Gibt es das Werkzeug nicht oder meldet es einen Fehler: einmal kurz sagen, nicht wiederholen.",
        $feld, $sek, $ref, epoch2iso($von), epoch2iso($z->{offen_bis} // $von), epoch2iso($von), int($sek / 60 + 0.5), $aufgabe);
}

sub verbuche {
    my ($z, $sek, $bis) = @_;
    $z->{offen} -= $sek;
    $z->{offen} = 0 if $z->{offen} < 1;
    if ($z->{offen} > 0) { $z->{offen_von} = $bis } else { delete $z->{offen_von}; delete $z->{offen_bis} }
}

sub warten {
    my $h = shift;
    my $id = $h->{session_id} // return;
    return unless ($h->{notification_type} // 'permission_prompt') eq 'permission_prompt' || ($h->{message} // '') =~ /permission/i;
    my $z = lade($id);
    push @{ $z->{warten} }, time;
    speichere($id, $z);
}

sub gemeldet {
    my $h = shift;
    my $id = $h->{session_id} // return;
    my $z = lade($id);
    my $a = $z->{angebot} // return;
    my $ref = ($h->{tool_input} // {})->{ref} // '';
    return unless $ref eq $a->{ref};
    # MCP-Antworten kommen als [{type: text, text: "<JSON>"}] (gemessen
    # 19.10.2026, Claude Code 2.1.296). booked, logged_only,
    # already_reported: erledigt. Ein Fehler: offen lassen, das Plugin bietet
    # dieselbe Referenz später wieder an.
    my $r = $h->{tool_response};
    my @teile = ref $r eq 'ARRAY' ? @$r : ref $r eq 'HASH' ? ($r->{content} ? @{ $r->{content} } : ($r)) : ({ text => $r // '' });
    my $status = '';
    for my $t (@teile) {
        my $inhalt = ref $t eq 'HASH' ? ($t->{text} // $t) : $t;
        my $d = ref $inhalt ? $inhalt : eval { JSON::PP->new->decode($inhalt) };
        if (ref $d eq 'HASH' && $d->{status}) { $status = $d->{status}; last }
    }
    return unless $status =~ /^(booked|logged_only|already_reported)$/;
    verbuche($z, $a->{sekunden}, $a->{bis});
    delete $z->{angebot};
    $z->{gemeldet_total} = ($z->{gemeldet_total} // 0) + $a->{sekunden};
    speichere($id, $z);
}
