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
5. Öffne **Authentication → URL Configuration**. Setze **Site URL** auf die Website-Adresse und ergänze unter **Redirect URLs** alle verwendeten Adressen, zum Beispiel `http://localhost:4173/**` sowie deine veröffentlichte Domain.

Es ist keine Google-Konfiguration erforderlich. Im Login-Bereich können Nutzer zwischen **Anmelden** und **Konto erstellen** wechseln. Der Fahrername ist optional. Der Link zum Zurücksetzen des Passworts verwendet dieselben Redirect-Adressen.

Neue Konten erhalten einmalig ein **3.000-Coins-Willkommensgeschenk**. Der Bonus wird erst nach Klick auf **Geschenk claimen** gutgeschrieben. Bestehende Konten sind von diesem Registrierungsbonus ausgeschlossen. Nach einer Schemaänderung `schema.sql` erneut ausführen.

## 3. Admin-Zugang (optional)

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