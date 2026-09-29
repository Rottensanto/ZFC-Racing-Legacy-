function filterCards(){
 const q=(document.getElementById('search')?.value||'').toLowerCase();
 const r=document.getElementById('rarityFilter')?.value||'all';
 const s=document.getElementById('sortFilter')?.value||'rating';
 const arrSource=currentUser?userCards:[];
 let arr=arrSource.filter(c=>(r==='all'||c.rarity===r)&&(`${c.name} ${c.short} ${c.year}`.toLowerCase().includes(q)));
 arr.sort((a,b)=>s==='rating'?b.rating-a.rating:s==='year'?b.year-a.year:a.name.localeCompare(b.name));
 const grid=document.getElementById('collectionGrid');if(grid)grid.innerHTML=arr.map(card=>cardHTML(card,true)).join('');
 const message=document.getElementById('collectionMessage');if(message)message.textContent=currentUser?(arr.length?`${arr.length} Karten in deiner Sammlung.`:'Noch keine Karten gesammelt. Öffne dein erstes Pack im Shop.'):'Melde dich an, um deine persönliche Sammlung zu sehen.';
}
async function sellCard(instanceId){
 if(!currentUser||!backendReady())return showPage('login');
 if(!confirm('Diese Karte zum angezeigten Stufen- und Levelwert verkaufen?'))return;
 const {data,error}=await supabaseClient.rpc('sell_user_card',{p_instance_id:instanceId});
 if(error)return displayBackendError(error);
 await refreshAccountData();
 toast(`${data.card} verkauft: ${Number(data.coins_awarded).toLocaleString()} Coins.`);
}
async function upgradeCard(instanceId){
 if(!currentUser||!backendReady())return showPage('login');
 const {data,error}=await supabaseClient.rpc('upgrade_user_card',{p_instance_id:instanceId});
 if(error)return displayBackendError(error);
 await refreshAccountData();
 toast(`Karte auf Level ${data.level} verbessert · ${Number(data.coins_spent).toLocaleString()} Coins.`);
}
