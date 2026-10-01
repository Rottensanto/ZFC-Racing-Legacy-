let supabaseClient = null;
let authMode = 'login';
let adminPlayersPage = 0;
const ADMIN_PLAYER_PAGE_SIZE = 30;

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
 const rawMessage = error?.message || '';
 const friendlyMessages = [
  [/invalid login credentials/i, 'E-Mail oder Passwort ist falsch.'],
  [/user already registered/i, 'Für diese E-Mail gibt es bereits ein Konto. Melde dich an oder setze dein Passwort zurück.'],
  [/password should be at least/i, 'Das Passwort muss mindestens 8 Zeichen haben.'],
  [/email not confirmed/i, 'Bitte bestätige zuerst deine E-Mail-Adresse.'],
  [/failed to fetch|fetch failed/i, 'Supabase ist nicht erreichbar. Prüfe deine Projekt-URL und Internetverbindung.']
 ];
 const message = friendlyMessages.find(([pattern]) => pattern.test(rawMessage))?.[1]
   || rawMessage
   || 'Aktion fehlgeschlagen. Bitte erneut versuchen.';
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
 if (accountProfile?.welcome_bonus_claimed_at === null) showWelcomeBonus();
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
     const text = row.kind === 'welcome_bonus' ? `+${Number(row.coins_delta).toLocaleString()} COINS · ZFC WILLKOMMENSGESCHENK`
       : row.kind === 'pack_purchase' ? `${String(detail.tier || 'F1').toUpperCase()} PACK GEÖFFNET`
       : row.kind === 'card_sale' ? `${detail.card || 'Karte'} · LEVEL ${detail.level || 1} VERKAUFT`
       : row.kind === 'card_upgrade' ? `KARTE AUF LEVEL ${detail.new_level || ''} VERBESSERT`
       : `+${Number(row.coins_delta).toLocaleString()} COINS UMGETAUSCHT`;
     return { text, createdAt: row.created_at };
   }),
   ...pointRows.map(row => ({
     text: `+${Number(row.points_delta).toLocaleString()} F1-PUNKTE · ${row.event_name}${row.finish_position ? ` · P${row.finish_position}` : ''}`,
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
 const progressXp = Math.max(0, Number(accountProfile?.progress_xp || 0));
 const levelProgressXp = progressXp % 25000;
 setText('playerLevel', String(Math.floor(progressXp / 25000) + 1));
 setText('levelProgressText', `${levelProgressXp.toLocaleString()} / 25.000 XP`);
 const levelProgressBar = document.getElementById('levelProgressBar');
 if (levelProgressBar) levelProgressBar.style.width = `${(levelProgressXp / 25000) * 100}%`;
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

function showWelcomeBonus() {
 const modal = document.getElementById('welcomeBonusModal');
 const claimButton = document.getElementById('welcomeBonusClaim');
 if (!modal || modal.classList.contains('open')) return;
 claimButton.disabled = false;
 claimButton.textContent = 'GESCHENK CLAIMEN';
 modal.classList.add('open');
 claimButton.focus();
}

async function claimWelcomeBonus() {
 if (!requireBackend() || !currentUser) return;
 const modal = document.getElementById('welcomeBonusModal');
 const claimButton = document.getElementById('welcomeBonusClaim');
 claimButton.disabled = true;
 claimButton.textContent = 'WIRD VERBUCHT ...';

 const { data, error } = await supabaseClient.rpc('claim_welcome_bonus');
 if (error) {
   displayBackendError(error);
   claimButton.disabled = false;
   claimButton.textContent = 'ERNEUT VERSUCHEN';
   return;
 }

 await refreshAccountData();
 modal.classList.remove('open');
 toast(`${Number(data.coins_awarded).toLocaleString()} Coins wurden deinem Konto gutgeschrieben.`);
}

function setAuthMode(mode) {
 authMode = mode === 'signup' ? 'signup' : 'login';
 const isSignup = authMode === 'signup';
 document.getElementById('signupNameField')?.classList.toggle('hidden', !isSignup);
 document.getElementById('loginPassword').autocomplete = isSignup ? 'new-password' : 'current-password';
 document.getElementById('authSubmitButton').textContent = isSignup ? 'KONTO ERSTELLEN' : 'ANMELDEN';
 document.getElementById('authLoginMode').classList.toggle('red', !isSignup);
 document.getElementById('authSignupMode').classList.toggle('red', isSignup);
 document.getElementById('authLoginMode').setAttribute('aria-pressed', String(!isSignup));
 document.getElementById('authSignupMode').setAttribute('aria-pressed', String(isSignup));
 setAuthMessage(isSignup ? 'Lege dein Konto mit E-Mail und einem Passwort mit mindestens 8 Zeichen an.' : 'E-Mail und Passwort eingeben.');
}

function submitAuthForm(event) {
 event.preventDefault();
 if (authMode === 'signup') createAccount();
 else loginWithPassword();
}

async function loginWithDiscord() {
 if (!requireBackend()) return;
 const redirectTo = window.APP_CONFIG.authRedirectUrl || `${window.location.origin}${window.location.pathname}`;
 const { error } = await supabaseClient.auth.signInWithOAuth({
   provider: 'discord',
   options: { redirectTo, scopes: 'identify email' }
 });
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
 else setAuthMessage('Konto erstellt. Prüfe dein E-Mail-Postfach, falls eine Bestätigung aktiviert ist.');
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

async function adminSearchPlayers(page = 0) {
 if (!backendReady() || !isAdmin) return toast('Admin-Berechtigung erforderlich.');
 page = Math.max(0, Number(page) || 0);
 const query = document.getElementById('adminSearchEmail').value.trim();
 const start = page * ADMIN_PLAYER_PAGE_SIZE;
 let request = supabaseClient.from('profiles')
   .select('email,display_name,coins,f1_points', { count: 'exact' })
   .order('display_name', { ascending: true })
   .range(start, start + ADMIN_PLAYER_PAGE_SIZE - 1);
 if (query) request = request.ilike('email', `%${query}%`);
 const result = await request;
 if (result.error) return displayBackendError(result.error);
 adminPlayersPage = page;
 const total = result.count || 0;
 const status = document.getElementById('adminPageStatus');
 if (status) status.textContent = total
   ? `Konten ${start + 1}–${Math.min(start + result.data.length, total)} von ${total}`
   : 'Keine Konten gefunden.';
 document.getElementById('adminPreviousPage').disabled = page === 0;
 document.getElementById('adminNextPage').disabled = start + ADMIN_PLAYER_PAGE_SIZE >= total;
 const output = document.getElementById('adminUsers');
 output.replaceChildren();
 for (const profile of result.data) {
   const row = document.createElement('div');
   row.className = 'admin-user-row';
   const identity = document.createElement('div');
   identity.className = 'admin-user-identity';
   const name = document.createElement('strong');
   name.textContent = profile.display_name || 'F1 Driver';
   const email = document.createElement('span');
   email.textContent = profile.email;
   const balances = document.createElement('small');
   balances.textContent = `${Number(profile.f1_points).toLocaleString()} F1-Punkte · ${Number(profile.coins).toLocaleString()} Coins`;
   identity.append(name, email, balances);

   const award = document.createElement('details');
   award.className = 'admin-inline-award';
   const summary = document.createElement('summary');
   summary.textContent = 'PUNKTE VERGEBEN';
   const controls = document.createElement('div');
   controls.className = 'admin-inline-controls';
   const eventInput = document.createElement('input');
   eventInput.type = 'text';
   eventInput.placeholder = 'Rennen / Event';
   eventInput.setAttribute('aria-label', `Rennen oder Event für ${profile.email}`);
   const positionSelect = document.createElement('select');
   positionSelect.setAttribute('aria-label', `Platzierung für ${profile.email}`);
   const racePoints = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1];
   racePoints.forEach((points, index) => {
     const option = document.createElement('option');
     option.value = String(index + 1);
     option.textContent = `${index + 1}. Platz · ${points} Punkte`;
     positionSelect.append(option);
   });
   const awardButton = document.createElement('button');
   awardButton.type = 'button';
   awardButton.className = 'btn red';
   awardButton.textContent = 'VERBUCHEN';
   awardButton.addEventListener('click', () => adminAwardRacePoints(profile.email, eventInput.value, positionSelect.value, award));
   const placementRow = document.createElement('div');
   placementRow.className = 'admin-inline-row';
   placementRow.append(positionSelect, awardButton);
   const customPointsInput = document.createElement('input');
   customPointsInput.type = 'number';
   customPointsInput.min = '1';
   customPointsInput.step = '1';
   customPointsInput.placeholder = 'F1-Punkte direkt eingeben';
   customPointsInput.setAttribute('aria-label', `F1-Punkte für ${profile.email}`);
   const customAwardButton = document.createElement('button');
   customAwardButton.type = 'button';
   customAwardButton.className = 'btn';
   customAwardButton.textContent = 'PUNKTE GUTSCHREIBEN';
   customAwardButton.addEventListener('click', () => adminAwardCustomPoints(profile.email, eventInput.value, customPointsInput.value, award));
   const customPointsRow = document.createElement('div');
   customPointsRow.className = 'admin-inline-row';
   customPointsRow.append(customPointsInput, customAwardButton);
   controls.append(eventInput, placementRow, customPointsRow);
   award.append(summary, controls);
   row.append(identity, award);
   output.append(row);
 }
}

function adminPreviousPlayersPage() {
 return adminSearchPlayers(adminPlayersPage - 1);
}

function adminNextPlayersPage() {
 return adminSearchPlayers(adminPlayersPage + 1);
}

async function adminAwardRacePoints(emailOverride, eventOverride, positionOverride, inlineAward) {
 if (!requireBackend() || !isAdmin) return toast('Admin-Berechtigung erforderlich.');
 const email = String(emailOverride ?? document.getElementById('awardEmail').value).trim();
 const position = Number(positionOverride ?? document.getElementById('awardPosition').value);
 const eventName = String(eventOverride ?? document.getElementById('awardEvent').value).trim();
 if (!email || !eventName) return toast('Spieler-E-Mail und Rennen/Event eingeben.');
 const { data, error } = await supabaseClient.rpc('admin_award_race_points', {
   p_email: email,
   p_position: position,
   p_event_name: eventName
 });
 if (error) return displayBackendError(error);
 if (data.already_awarded) {
   toast(`Punkte für ${email} bei "${eventName}" wurden bereits vergeben.`);
   if (inlineAward) inlineAward.open = false;
   await adminSearchPlayers(adminPlayersPage);
   return;
 }
 toast(`${data.f1_points_awarded.toLocaleString()} F1-Punkte an ${email} vergeben.`);
 if (inlineAward) inlineAward.open = false;
 await adminSearchPlayers(adminPlayersPage);
}

async function adminAwardCustomPoints(email, eventName, pointsValue, inlineAward) {
 if (!requireBackend() || !isAdmin) return toast('Admin-Berechtigung erforderlich.');
 const pointsToAward = Number(pointsValue);
 const awardEvent = String(eventName ?? '').trim();
 if (!Number.isSafeInteger(pointsToAward) || pointsToAward < 1) return toast('Mindestens einen F1-Punkt als ganze Zahl eingeben.');
 if (!awardEvent) return toast('Rennen oder Event eingeben.');

 const { data, error } = await supabaseClient.rpc('admin_award_custom_points', {
   p_email: email,
   p_points: pointsToAward,
   p_event_name: awardEvent
 });
 if (error) return displayBackendError(error);
 if (data.already_awarded) {
   toast(`Punkte für ${email} bei "${awardEvent}" wurden bereits vergeben.`);
 } else {
   toast(`${Number(data.points_awarded).toLocaleString()} F1-Punkte an ${email} vergeben.`);
 }
 if (inlineAward) inlineAward.open = false;
 await adminSearchPlayers(adminPlayersPage);
}