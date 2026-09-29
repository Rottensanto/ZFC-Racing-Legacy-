let supabaseClient = null;

function setAuthMessage(message, isError = false) {
 const target = document.getElementById('authMessage');
 if (!target) return;
 target.textContent = message;
 target.classList.toggle('error', isError);
}

function backendReady() {
 return Boolean(supabaseClient);
}

function requireBackend() {
 if (supabaseClient) return true;
 setAuthMessage('Supabase ist noch nicht konfiguriert. URL und Anon-Key in scripts/config.js eintragen.', true);
 return false;
}

function displayBackendError(error) {
 const message = error?.message || 'Aktion fehlgeschlagen. Bitte erneut versuchen.';
 setAuthMessage(message, true);
 toast(message);
}

async function initializeBackend() {
 const config = window.APP_CONFIG || {};
 if (!config.supabaseUrl || !config.supabaseAnonKey || !window.supabase?.createClient) {
   setAuthMessage('Supabase-Projekt verbinden, um Konten geräteübergreifend zu nutzen.', true);
   return;
 }

 supabaseClient = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey, {
   auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
 });

 const { data: { session }, error } = await supabaseClient.auth.getSession();
 if (error) displayBackendError(error);
 await applyAuthSession(session);
 supabaseClient.auth.onAuthStateChange((_event, nextSession) => {
   window.setTimeout(() => applyAuthSession(nextSession), 0);
 });
}

async function applyAuthSession(session) {
 currentUser = session?.user || null;
 accountProfile = null;
 userCards = [];
 isAdmin = false;
 if (!currentUser || !supabaseClient) {
  coins=0;points=0;
   updateAccountUI();
   render();
   return;
 }

 const [profileResult, cardsResult, adminResult, coinActivity, pointActivity] = await Promise.all([
   supabaseClient.from('profiles').select('*').eq('id', currentUser.id).single(),
   supabaseClient.from('user_cards').select('id,level,obtained_at,card:cards(*)').eq('user_id', currentUser.id).order('obtained_at', { ascending: false }),
   supabaseClient.rpc('is_admin'),
   supabaseClient.from('coin_ledger').select('coins_delta,kind,detail,created_at').eq('user_id', currentUser.id).order('created_at', { ascending: false }).limit(8),
   supabaseClient.from('point_ledger').select('points_delta,event_name,finish_position,created_at').eq('user_id', currentUser.id).order('created_at', { ascending: false }).limit(8)
 ]);

 if (profileResult.error) displayBackendError(profileResult.error);
 else accountProfile = profileResult.data;
 coins=Number(accountProfile?.coins || 0);
 points=Number(accountProfile?.f1_points || 0);
 if (cardsResult.error) displayBackendError(cardsResult.error);
 else userCards = (cardsResult.data || []).filter(row => row.card).map(row => ({
   instanceId: row.id,
   level: row.level,
   name: row.card.name,
   short: row.card.short_name,
   year: row.card.card_year,
   rating: row.card.rating,
   rarity: row.card.rarity,
   type: row.card.card_type,
   img: row.card.image_url
 }));
 if (adminResult.error) displayBackendError(adminResult.error);
 else isAdmin = adminResult.data === true;
 if (coinActivity.error) displayBackendError(coinActivity.error);
 if (pointActivity.error) displayBackendError(pointActivity.error);

 updateAccountUI();
 renderRecentActivity(coinActivity.data || [], pointActivity.data || []);
 if (currentUser) setAuthMessage(`Angemeldet als ${currentUser.email}.`);
 render();
 updateConvert();
}

function renderRecentActivity(coinRows, pointRows) {
 const target = document.getElementById('activity');
 if (!target) return;
 const events = [
   ...coinRows.map(row => {
     const detail = row.detail || {};
     const text = row.kind === 'pack_purchase' ? `${String(detail.tier || 'F1').toUpperCase()} PACK GEÖFFNET`
       : row.kind === 'card_sale' ? `${detail.card || 'Karte'} · LEVEL ${detail.level || 1} VERKAUFT`
       : row.kind === 'card_upgrade' ? `KARTE AUF LEVEL ${detail.new_level || ''} VERBESSERT`
       : `+${Number(row.coins_delta).toLocaleString()} COINS UMGETAUSCHT`;
     return { text, createdAt: row.created_at };
   }),
   ...pointRows.map(row => ({
     text: `+${Number(row.points_delta).toLocaleString()} F1-PUNKTE · ${row.event_name} · P${row.finish_position}`,
     createdAt: row.created_at
   }))
 ].sort((a,b) => new Date(b.createdAt)-new Date(a.createdAt)).slice(0,6);
 target.replaceChildren();
 if (!events.length) {
   target.textContent='Noch keine Kontoaktivitäten.';
   return;
 }
 for (const event of events) {
   const row=document.createElement('div');
   row.className='activity-row';
   row.textContent=`${event.text} · ${new Date(event.createdAt).toLocaleDateString()}`;
   target.append(row);
 }
}

function updateAccountUI() {
 const name = accountProfile?.display_name || currentUser?.email?.split('@')[0] || 'F1 Driver';
 const email = currentUser?.email || '';
 const setText = (id, value) => {
   const element = document.getElementById(id);
   if (element) element.textContent = value;
 };
 setText('accountName', name);
 setText('accountEmail', email);
 setText('accountCoins', (accountProfile?.coins || 0).toLocaleString());
 setText('accountPoints', (accountProfile?.f1_points || 0).toLocaleString());
 setText('welcomeName', name);
 setText('coinCount', (accountProfile?.coins || 0).toLocaleString());
 setText('dashCoins', (accountProfile?.coins || 0).toLocaleString());
 setText('pointCount', (accountProfile?.f1_points || 0).toLocaleString());
 setText('dashPoints', (accountProfile?.f1_points || 0).toLocaleString());
 setText('loginTop', currentUser ? 'PROFILE' : 'LOGIN');
 const avatar = document.getElementById('avatarInitials');
 if (avatar) avatar.textContent = name.split(/\s+/).map(part => part[0]).join('').slice(0, 2).toUpperCase();
 const logoutButton = document.getElementById('logoutButton');
 if (logoutButton) logoutButton.classList.toggle('hidden', !currentUser);
 const adminLink = document.getElementById('adminNav');
 if (adminLink) adminLink.classList.toggle('hidden', !isAdmin);
 const adminPage = document.getElementById('admin');
 if (adminPage) adminPage.classList.toggle('hidden', !isAdmin);
 const collectionValue = document.getElementById('collectionValue');
 if (collectionValue) collectionValue.textContent = userCards.length.toLocaleString();
 setText('dashCardCount', userCards.length.toLocaleString());
}

async function loginWithGoogle() {
 if (!requireBackend()) return;
 const redirectTo = window.APP_CONFIG.authRedirectUrl || `${window.location.origin}${window.location.pathname}`;
 const { error } = await supabaseClient.auth.signInWithOAuth({ provider: 'google', options: { redirectTo } });
 if (error) displayBackendError(error);
}

async function loginWithPassword() {
 if (!requireBackend()) return;
 const email = document.getElementById('loginUser').value.trim();
 const password = document.getElementById('loginPassword').value;
 if (!email || !password) return setAuthMessage('E-Mail und Passwort eingeben.', true);
 const { error } = await supabaseClient.auth.signInWithPassword({ email, password });
 if (error) displayBackendError(error);
 else setAuthMessage('Anmeldung erfolgreich.');
}

async function createAccount() {
 if (!requireBackend()) return;
 const email = document.getElementById('loginUser').value.trim();
 const password = document.getElementById('loginPassword').value;
 const name = document.getElementById('signupName').value.trim();
 if (!email || password.length < 8) return setAuthMessage('E-Mail und ein Passwort mit mindestens 8 Zeichen eingeben.', true);
 const { error } = await supabaseClient.auth.signUp({
   email,
   password,
   options: {
     data: { full_name: name || email.split('@')[0] },
     emailRedirectTo: window.APP_CONFIG.authRedirectUrl || `${window.location.origin}${window.location.pathname}`
   }
 });
 if (error) displayBackendError(error);
 else setAuthMessage('Konto erstellt. Bitte bestätige deine E-Mail, falls Supabase dies verlangt.');
}

async function resetAccountPassword() {
 if (!requireBackend()) return;
 const email = document.getElementById('loginUser').value.trim();
 if (!email) return setAuthMessage('Zum Zurücksetzen zuerst deine E-Mail eingeben.', true);
 const { error } = await supabaseClient.auth.resetPasswordForEmail(email, {
   redirectTo: window.APP_CONFIG.authRedirectUrl || `${window.location.origin}${window.location.pathname}`
 });
 if (error) displayBackendError(error);
 else setAuthMessage('Link zum Zurücksetzen wurde angefordert.');
}

async function setAccountPassword() {
 if (!requireBackend() || !currentUser) return;
 const password = document.getElementById('newAccountPassword').value;
 if (password.length < 8) return setAuthMessage('Das neue Passwort muss mindestens 8 Zeichen haben.', true);
 const { error } = await supabaseClient.auth.updateUser({ password });
 if (error) displayBackendError(error);
 else {
   document.getElementById('newAccountPassword').value = '';
   setAuthMessage('Eigenes Passwort wurde gespeichert.');
 }
}

async function logoutAccount() {
 if (!requireBackend()) return;
 const { error } = await supabaseClient.auth.signOut();
 if (error) displayBackendError(error);
 else showPage('home');
}

async function refreshAccountData() {
 if (!currentUser || !supabaseClient) return;
 await applyAuthSession({ user: currentUser });
}

async function adminSearchPlayers() {
 if (!requireBackend() || !isAdmin) return toast('Admin-Berechtigung erforderlich.');
 const query = document.getElementById('adminSearchEmail').value.trim();
 const result = await supabaseClient.from('profiles').select('email,display_name,coins,f1_points').ilike('email', `%${query}%`).order('display_name').limit(25);
 if (result.error) return displayBackendError(result.error);
 const output = document.getElementById('adminUsers');
 output.replaceChildren();
 for (const profile of result.data) {
   const row = document.createElement('div');
   row.className = 'admin-user-row';
   row.textContent = `${profile.display_name} · ${profile.email} · ${profile.f1_points.toLocaleString()} F1 P · ${profile.coins.toLocaleString()} C`;
   output.append(row);
 }
}

async function adminAwardRacePoints() {
 if (!requireBackend() || !isAdmin) return toast('Admin-Berechtigung erforderlich.');
 const email = document.getElementById('awardEmail').value.trim();
 const position = Number(document.getElementById('awardPosition').value);
 const eventName = document.getElementById('awardEvent').value.trim();
 if (!email || !eventName) return setAuthMessage('Spieler-E-Mail und Event eingeben.', true);
 const { data, error } = await supabaseClient.rpc('admin_award_race_points', {
   p_email: email,
   p_position: position,
   p_event_name: eventName
 });
 if (error) return displayBackendError(error);
 toast(`${data.f1_points_awarded.toLocaleString()} F1-Punkte an ${email} vergeben.`);
 await adminSearchPlayers();
}