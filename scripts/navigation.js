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
 const range=document.getElementById('convertRange');
 const maximum=Math.floor(Math.max(0,Number(points)||0)/10)*10;
 if(range.dataset.maximum!==String(maximum)){
	 range.max=String(maximum);
	 range.value=String(maximum);
	 range.dataset.maximum=String(maximum);
 }
 const used=Math.min(Math.floor(Number(range.value)/10)*10,maximum);
 const receive=(used/10)*90;
 range.value=String(used);
 document.getElementById('availablePoints').textContent=Number(points||0).toLocaleString();
 document.getElementById('usedPoints').textContent=used.toLocaleString();
 document.getElementById('receiveCoins').textContent=receive.toLocaleString()+' C';
}
function setConvertMaximum(){
 const range=document.getElementById('convertRange');
 range.value=range.max;
 updateConvert();
}
async function convertPoints(){
 if(!currentUser||!backendReady())return showPage('login');
 const used=Number(document.getElementById('convertRange').value);
 if(used<=0){toast('Wähle zuerst einen Umwandlungswert.');return}
 const {data,error}=await supabaseClient.rpc('convert_f1_points',{p_points:used});
 if(error)return displayBackendError(error);
 await refreshAccountData();
 toast(`${data.points_spent.toLocaleString()} F1-Punkte in ${data.coins_awarded.toLocaleString()} Coins umgetauscht.`);
}
