# Supabase einrichten

Die Website verwendet E-Mail und Passwort. Neue Konten bekommen automatisch ein Profil; du musst dafür keine Nutzer manuell in der Datenbank anlegen.

## 1. Projekt verbinden

1. Erstelle ein Projekt unter [supabase.com](https://supabase.com/).
2. Öffne im Dashboard **SQL Editor**, füge den gesamten Inhalt aus `schema.sql` ein und führe ihn aus.
3. Öffne **Project Settings → API**. Kopiere die **Project URL** und den **Publishable key** (bei älteren Projekten heißt dieser `anon` key).
4. Trage beide Werte in `scripts/config.js` ein. Die URL endet auf `.supabase.co` und darf **nicht** `/rest/v1/` enthalten. Den `service_role`-Key niemals in die Website eintragen.

Beispiel:

```js
window.APP_CONFIG = Object.freeze({
  supabaseUrl: 'https://DEINE-PROJEKT-ID.supabase.co',
  supabaseAnonKey: 'DEIN_PUBLISHABLE_KEY',
  authRedirectUrl: ''
});
```

## 2. E-Mail und Passwort einstellen

1. Öffne **Authentication → Sign In / Providers → Email** und aktiviere E-Mail-Anmeldung.
2. Stelle eine Mindestlänge von **8 Zeichen** für Passwörter ein.
3. Für den einfachsten Einstieg schalte **Confirm email** aus. Nach der Registrierung ist das Konto dann sofort angemeldet.
4. Für eine öffentliche oder produktive Website schalte **Confirm email** ein und richte unter **Authentication → SMTP Settings** einen eigenen E-Mail-Versand ein. Neue Nutzer müssen dann erst den Bestätigungslink anklicken.
5. Richte die Rückleitung wie im nächsten Abschnitt beschrieben ein.

### Bestätigungslink auf GitHub Pages

Die veröffentlichte Website liegt unter dieser Adresse. Pfad und abschließender Schrägstrich müssen genau so stimmen:

```text
https://rottensanto.github.io/ZFC-Racing-Legacy-/
```

1. Öffne im Supabase-Dashboard **Authentication → URL Configuration**.
2. Trage unter **Site URL** exakt `https://rottensanto.github.io/ZFC-Racing-Legacy-/` ein und speichere.
3. Füge unter **Redirect URLs** beide folgenden Einträge hinzu und speichere erneut:

```text
https://rottensanto.github.io/ZFC-Racing-Legacy-/
https://rottensanto.github.io/ZFC-Racing-Legacy-/**
```

4. Falls du lokal testest, ergänze zusätzlich `http://localhost:4173/**` (nur wenn dein lokaler Server tatsächlich Port 4173 verwendet).
5. Prüfe unter **Authentication → Email Templates → Confirm signup**, dass der Bestätigungsbutton auf `{{ .ConfirmationURL }}` verweist. Ersetze diesen Link nicht durch `{{ .SiteURL }}`: Supabase muss zuerst die Adresse bestätigen und leitet danach zur Website weiter.
6. `scripts/config.js` muss denselben Zielpfad enthalten:

```js
authRedirectUrl: 'https://rottensanto.github.io/ZFC-Racing-Legacy-/'
```

Danach eine **neue** Registrierung testen und den neuesten Bestätigungslink verwenden; ältere Links können abgelaufen sein. Der richtige Ablauf führt kurz über Supabase und anschließend auf die Projekt-Startseite. Ein zusätzlicher Pfad wie `/auth/callback` oder `/index.html` ist für diese Website nicht nötig.

**Wenn weiterhin ein Fehler erscheint:** Bei „Redirect URL not allowed“ die Redirect-URL-Zeichen einschließlich Bindestrich und abschließendem `/` mit den beiden Einträgen oben vergleichen. Bei einer GitHub-Pages-404 prüfen, dass der Link auf `/ZFC-Racing-Legacy-/` zeigt und nicht auf die Domainwurzel `/` oder einen erfundenen Callback-Pfad. Die GitHub-Pages-Zielseite selbst ist unter der oben genannten Adresse erreichbar.

Es ist keine Google-Konfiguration erforderlich. Im Login-Bereich können Nutzer zwischen **Anmelden** und **Konto erstellen** wechseln. Der Fahrername ist optional. Der Link zum Zurücksetzen des Passworts verwendet dieselben Redirect-Adressen.

## 3. Discord-Login aktivieren

Die Website bietet Discord zusätzlich zu E-Mail und Passwort an. Der Discord-Client-Schlüssel wird nur in Supabase gespeichert, niemals in `scripts/config.js`.

1. Öffne das [Discord Developer Portal](https://discord.com/developers/applications) und erstelle eine Application für deine Website.
2. Öffne in der Application **OAuth2 → General**. Kopiere **Client ID** und **Client Secret**.
3. Trage unter **Redirects** exakt diese Callback-URL ein und speichere:

```text
https://pwgjdapfjtbggpnqipax.supabase.co/auth/v1/callback
```

4. Öffne im Supabase-Dashboard **Authentication → Sign In / Providers → Discord** und aktiviere Discord.
5. Füge dort die **Client ID** und das **Client Secret** aus Discord ein und speichere. Falls Supabase ein Feld **Scopes** anzeigt, müssen `identify email` gesetzt sein. Discord muss eine E-Mail-Adresse freigeben, weil das Spielerprofil eine E-Mail benötigt.
6. Behalte unter **Authentication → URL Configuration** die GitHub-Pages-Adresse als **Site URL** und die Redirect-URLs aus dem vorigen Abschnitt bei. `scripts/config.js` muss weiter auf `https://rottensanto.github.io/ZFC-Racing-Legacy-/` zurückleiten.
7. Öffne die Website, wähle **Mit Discord anmelden** und bestätige den Zugriff. Discord leitet zuerst an Supabase zurück; Supabase leitet danach zur Website weiter.

Wichtig: Die Callback-URL im Discord Portal ist die Supabase-Adresse oben. Sie ist **nicht** die GitHub-Pages-Adresse. GitHub Pages wird stattdessen als erlaubtes `redirectTo`-Ziel bei Supabase eingetragen.

Neue Konten erhalten einmalig ein **3.000-Coins-Willkommensgeschenk**. Der Bonus wird erst nach Klick auf **Geschenk claimen** gutgeschrieben. Bestehende Konten sind von diesem Registrierungsbonus ausgeschlossen. Nach einer Schemaänderung `schema.sql` erneut ausführen.

Spieler starten auf **Level 1**. Alle 25.000 XP steigt das Level um eins. Verdiente Coins (Willkommensbonus, Kartenverkauf und Punkteumtausch) sowie der Preis gekaufter Packs zählen dauerhaft als XP. Ausgegebene Coins ziehen keine XP ab. Bestehende Profile starten beim Schema-Update ebenfalls auf Level 1.

## 4. Admin-Zugang (optional)

Erstelle zunächst ein Konto über die Website. Ersetze danach im SQL-Befehl die Beispieladresse durch die E-Mail-Adresse dieses Kontos und führe ihn im Supabase **SQL Editor** aus:

```sql
insert into public.user_roles (user_id, role)
select id, 'admin'
from auth.users
where lower(email) = lower('admin@example.com')
on conflict (user_id) do update set role = 'admin';
```

Die Adminrolle lässt sich nicht über die Website vergeben. Das Schema erstellt für jedes neue Auth-Konto automatisch ein Profil und schützt Kontodaten mit Row Level Security.

## Spielregeln

- F1-Platzierungspunkte: 25, 18, 15, 12, 10, 8, 6, 4, 2, 1 für Platz 1 bis 10. Die Gutschrift wird mit 100 multipliziert.
- Umtausch: 10 F1-Punkte ergeben 1 Coin, maximal 500 Coins pro UTC-Kalendertag.
- Kartenverkauf wird serverseitig nach Kartenstufe, Rating und Kartenlevel berechnet.
- Karten starten auf Level 1; ein Levelaufstieg kostet `aktuelles Level × 300` Coins, bis maximal Level 10.
- Packpreise: Bronze 1.000, Platinum 5.000, Gold 9.500, Legend 17.000 Coins.