# Holy MacBook

Ein großer Knopf, der dein MacBook auch zugeklappt wach hält, damit Claude Code lokal weiterlaufen kann.

- **An:** Das MacBook schläft nicht ein, auch nicht beim Zuklappen.
- **Aus:** Alles wie gewohnt.
- **Schutzabschaltung:** Das Wachhalten schaltet sich selbst ab, wenn der Akku im Akkubetrieb unter 10 % fällt oder der Lüfter anläuft. Ist der Deckel dabei zu, geht das MacBook direkt schlafen. Beide Regeln lassen sich im Fenster einzeln abschalten.

Die App hat ein Fenster mit dem Knopf und ein Symbol in der Menüleiste (abschaltbar in den Einstellungen, ⌘,).

## Bauen

Du brauchst macOS 13 oder neuer und Xcode oder die Command Line Tools (`xcode-select --install`).

```bash
./build.sh
open "build/Holy MacBook.app"
```

Zum Installieren die App nach `/Applications` kopieren:

```bash
cp -R "build/Holy MacBook.app" /Applications/
```

Zum Entwickeln kannst du `Package.swift` direkt in Xcode öffnen.

## Einmalige Einrichtung

Zugeklappt wach bleibt ein MacBook nur über `pmset -a disablesleep 1`, und dieser Befehl braucht Admin-Rechte. Beim ersten Start klickst du deshalb auf **Einrichten…** und gibst einmal dein Passwort ein. Die App legt dann die Datei `/etc/sudoers.d/holymacbook` an. Sie erlaubt deinem Benutzer genau zwei Befehle ohne Passwort:

```
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

Rückgängig machen: Menü **Wachhalten → Einrichtung entfernen…** oder von Hand `sudo rm /etc/sudoers.d/holymacbook`.

## Gut zu wissen

- Beim Beenden der App wird das Wachhalten ausgeschaltet. Die Schutzabschaltung läuft nur, solange die App läuft.
- Mit `--print-setup-command` statt `--diagnose` zeigt die App den Befehl, den die Einrichtung ausführt.
- Stürzt die App ab, während das Wachhalten an ist, bleibt es an. Beim nächsten Start zeigt der Knopf den echten Zustand. Notfalls im Terminal: `sudo pmset -a disablesleep 0`.
- Auf MacBooks ohne Lüfter (MacBook Air) achtet die App statt auf den Lüfter auf den Temperaturzustand von macOS.
- Ein wach gehaltenes, zugeklapptes MacBook gehört nicht in eine geschlossene Tasche.

## Fehlersuche

Was die App von Akku, Lüfter und Ruhezustand sieht, zeigt:

```bash
"build/Holy MacBook.app/Contents/MacOS/HolyMacBook" --diagnose
```
