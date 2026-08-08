# QuarryOS bei Hostinger

1. In hPanel `Websites` -> `Website hinzufuegen` -> `Web App bereitstellen` waehlen.
2. `quarryos-hostinger.zip` hochladen.
3. Anwendungstyp `Other`, Node.js 20 oder neuer und Entry-Datei `server.js` waehlen.
4. Es ist kein Build-Befehl und kein Output-Verzeichnis erforderlich.
5. Unter `Environment Variables` die Variable `QUARRYOS_API_KEY` mit einem langen zufaelligen Wert anlegen.
6. Bereitstellen und `https://DEINE-DOMAIN/api/health` aufrufen.

Nach einem Update der Dateien in Hostinger immer eine neue Bereitstellung
starten. Nur das Hochladen ersetzt eine bereits laufende Version nicht.
Danach das Dashboard einmal mit `Strg+F5` neu laden, damit der Browser keine
Dateien aus einer vorherigen Bereitstellung verwendet.

Wenn `Web App bereitstellen` nicht angeboten wird, unterstuetzt der gebuchte
Hostinger-Tarif keine serverseitige Node.js-Anwendung. Fuer diese Variante ist
Business Web Hosting oder ein Cloud-Tarif erforderlich.
