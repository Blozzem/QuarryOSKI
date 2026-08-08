# QuarryOS Web-Dashboard einrichten

Das Gateway verbindet zwei getrennte Netze: QuarryOS funkt innerhalb von
Minecraft über Rednet; der Gateway-Computer sendet diese Daten per HTTP an die
Web-API. Die Website spricht nur mit der API und niemals direkt mit Minecraft.
Das Dashboard zeigt den aktuellen Zickzack-Fortschritt als Live-Karte und die
16 Turtle-Slots. Slot 16 wird als feste Liquid-Guard-Reserve markiert.

## 1. Webserver starten

Installiere Node.js 20 oder neuer auf dem Rechner, auf dem die Homepage laufen
soll. Öffne PowerShell im QuarryOS-Ordner und starte:

```powershell
$env:QUARRYOS_API_KEY="HIER-EINEN-LANGEN-ZUFAELLIGEN-SCHLUESSEL-EINTRAGEN"
node .\web\server.js
```

Öffne danach `http://localhost:8080`. Für ein Gerät im selben Heimnetz verwende
`http://IP-DES-RECHNERS:8080`. Erlaube Port 8080 gegebenenfalls in der
Windows-Firewall nur für private Netzwerke.

## 2. Gateway in Minecraft aufstellen

Verwende einen separaten Advanced Computer mit Wireless oder Ender Modem. Nach
der normalen QuarryOS-Installation:

```lua
/quarryos/web_gateway.lua setup
```

Als URL gibst du die LAN-IP des Web-Rechners ein, zum Beispiel
`http://192.168.1.20:8080` (nicht `localhost`). Der API-Schlüssel muss exakt
dem Wert aus PowerShell entsprechen. Anschließend startest du:

```lua
/quarryos/web_gateway.lua
```

Das Setup installiert automatisch
`/startup/quarryos-web-gateway.lua`. Dadurch startet das Gateway nach jedem
Neustart des Computers erneut. Bei einem bereits eingerichteten Gateway kannst
du den Autostart nachträglich aktivieren:

```lua
/quarryos/web_gateway.lua autostart
```

Zum Entfernen dient `/quarryos/web_gateway.lua remove-autostart`. Existiert
bereits eine Datei namens `/startup` (statt eines Startup-Ordners), verändert
QuarryOS sie nicht. Ergänze dort in diesem Sonderfall manuell
`shell.run("/quarryos/web_gateway.lua")`.

## 3. Lokale IPs in CC:Tweaked erlauben

CC:Tweaked blockiert lokale IP-Adressen standardmäßig. Bei aktuellen Versionen
liegt die Datei in deinem Weltordner unter
`serverconfig/computercraft-server.toml`. Setze **vor** die vorhandene
`host = "$private"`-Deny-Regel eine Allow-Regel nur für die LAN-IP des
Web-Rechners (hier `192.168.1.20`):

```toml
[[http.rules]]
    host = "192.168.1.20"
    action = "allow"
```

Regeln werden der Reihe nach geprüft, daher muss diese Ausnahme vor der
privaten Sperrregel stehen. Starte Minecraft bzw. den Server anschließend neu.
Bei älteren CC:Tweaked-Versionen unterscheidet sich die Konfiguration; verwende
dann die offizielle Anleitung „Allowing access to local IPs“ auf tweaked.cc.

Prüfe auf dem Gateway:

```lua
http.checkURL("http://192.168.1.20:8080/api/health")
```

Das Ergebnis muss `true` sein.

## Sicherheit

- Veröffentliche Port 8080 nicht direkt im Internet. Nutze für externen Zugriff
  einen HTTPS-Reverse-Proxy oder ein VPN.
- Der API-Schlüssel erlaubt auch Steuerbefehle. Teile ihn nicht und speichere
  ihn nicht im Git-Repository.
- Webbefehle werden über den vorhandenen QuarryOS-Control-Kanal gesendet. Die
  Turtle übernimmt Pause-/Stop-Befehle nur an einem gespeicherten Zellrand.
- Fällt die API aus, arbeitet die Turtle normal weiter; nur Dashboard und
  Fernsteuerung sind bis zur Wiederverbindung nicht verfügbar.

## Öffentlich mit Hostinger und G-Portal

Für einen Minecraft-Server bei G-Portal darf im Gateway keine private
Heimnetz-IP stehen. Verwende eine öffentliche HTTPS-Adresse wie
`https://quarry.example.de`.

Hostinger unterstützt Node.js-Web-Apps im Business-Webhosting und in den
Cloud-Tarifen. In hPanel:

1. `Websites` → `Website hinzufügen` → `Web App bereitstellen` öffnen.
2. Den Inhalt des Ordners `web` als ZIP hochladen.
3. Als Anwendungstyp `Other`, als Entry-Datei `server.js` und Node.js 20 oder
   neuer auswählen. Es ist kein Build-Schritt erforderlich.
4. Unter `Environment Variables` eine Variable `QUARRYOS_API_KEY` mit einem
   langen zufälligen Schlüssel anlegen.
5. Eine Domain oder Subdomain verbinden und die Anwendung bereitstellen.

Hostinger setzt den benötigten Netzwerkport automatisch über `PORT`; dieser
wird von QuarryOS Web übernommen. HTTPS wird über die verbundene Domain
bereitgestellt. Teste danach im Browser:

```text
https://quarry.example.de/api/health
```

Auf dem G-Portal-Minecraft-Server stellst du einen Advanced Computer mit
Wireless- oder Ender-Modem auf und konfigurierst ihn mit:

```lua
/quarryos/web_gateway.lua setup
```

Als API-URL kommt `https://quarry.example.de` hinein, als Schlüssel exakt der
Wert aus Hostinger. Eine Freigabe privater IP-Adressen ist dabei nicht nötig.
Falls die öffentliche Domain durch eigene CC:Tweaked-HTTP-Regeln gesperrt ist,
muss sie in `world/serverconfig/computercraft-server.toml` erlaubt werden.
