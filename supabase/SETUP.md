# Supabase einrichten

## 1. Datenbank

1. Ein Supabase-Projekt anlegen.
2. `schema.sql` vollständig im Supabase SQL Editor ausführen.
3. Unter **Project Settings → API** die Project URL und den `anon`/Publishable Key kopieren.
4. Beide Werte in `scripts/config.js` bei `supabaseUrl` und `supabaseAnonKey` eintragen. Niemals den `service_role`-Key in diese Website kopieren.

## 2. Google und Passwort

1. Unter **Authentication → Providers** Google aktivieren und die Google OAuth Client-ID sowie das Client-Secret im Supabase Dashboard hinterlegen.
2. Die von Supabase angezeigte Callback-URL in der Google Cloud OAuth-Konfiguration als autorisierte Redirect-URL eintragen.
3. Unter **Authentication → URL Configuration** die Website-URL und die lokale Testadresse, zum Beispiel `http://localhost:4173/**`, als erlaubte Redirect-URLs ergänzen.
4. E-Mail/Passwort unter **Authentication → Providers → Email** aktivieren. E-Mail-Bestätigung eingeschaltet lassen.

## 3. Admin

Mit dem gewünschten Google-Konto einmal regulär registrieren und anschließend im Supabase SQL Editor genau diese E-Mail als einzige Admin-Rolle einsetzen:

```sql
insert into public.user_roles (user_id, role)
select id, 'admin'
from auth.users
where lower(email) = lower('s.barbosa.galaxy@gmail.com')
on conflict (user_id) do update set role = 'admin';
```

Die Adminrolle kann nicht über die Website vergeben werden. Der Adminbereich und die Punktevergabe werden zusätzlich in den Datenbankfunktionen geprüft.

## Spielregeln

- F1-Platzierungspunkte: 25, 18, 15, 12, 10, 8, 6, 4, 2, 1 für Platz 1 bis 10. Die Gutschrift wird mit 100 multipliziert.
- Umtausch: 10 F1-Punkte ergeben 1 Coin, maximal 500 Coins pro UTC-Kalendertag.
- Kartenverkauf wird serverseitig nach Kartenstufe, Rating und Kartenlevel berechnet.
- Karten starten auf Level 1; ein Levelaufstieg kostet `aktuelles Level × 300` Coins, bis maximal Level 10.
- Packpreise: Bronze 1.000, Platinum 5.000, Gold 9.500, Legend 17.000 Coins.