function showPage(id){
 if(['dashboard','collection','admin'].includes(id)&&!currentUser){id='login';setAuthMessage('Bitte zuerst mit deinem Konto anmelden.');}
 if(id==='admin'&&!isAdmin){id='dashboard';toast('Dieser Bereich ist nur für die Rennleitung.');}
 document.querySelectorAll('.page').forEach(p=>p.classList.remove('active'));
 const el=document.getElementById(id); if(el) el.classList.add('active');
 document.querySelectorAll('.nav a').forEach(a=>a.classList.toggle('active',a.dataset.nav===id));
 window.scrollTo({top:0,behavior:'smooth'});
 document.getElementById('loginTop').textContent=currentUser?'PROFILE':'LOGIN';
}
function toast(msg){
 const t=document.getElementById('toast');t.textContent=msg;t.classList.add('show');setTimeout(()=>t.classList.remove('show'),2800);
}
function updateConvert(){
 const pct=+document.getElementById('convertRange').value;
 const used=Math.floor(Math.floor(points*pct/100)/10)*10, receive=Math.min(used/10,500);
 document.getElementById('usedPoints').textContent=used.toLocaleString();
 document.getElementById('receiveCoins').textContent=receive.toLocaleString()+' C';
 document.getElementById('convertValue').textContent=pct+'% · MAX. 500 C/TAG';
}
async function convertPoints(){
 if(!currentUser||!backendReady())return showPage('login');
 const pct=+document.getElementById('convertRange').value;
 const used=Math.floor(Math.floor(points*pct/100)/10)*10;
 if(used<=0){toast('Wähle zuerst einen Umwandlungswert.');return}
 const {data,error}=await supabaseClient.rpc('convert_f1_points',{p_points:used});
 if(error)return displayBackendError(error);
 await refreshAccountData();
 toast(`${data.points_spent.toLocaleString()} F1-Punkte in ${data.coins_awarded.toLocaleString()} Coins umgetauscht.`);
}
