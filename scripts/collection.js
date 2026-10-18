const MAX_BULK_SALE_CARDS=6;
let bulkSellMode=false;
const selectedSaleCards=new Set();

function filterCards(){
 const q=(document.getElementById('search')?.value||'').toLowerCase();
 const r=document.getElementById('rarityFilter')?.value||'all';
 const s=document.getElementById('sortFilter')?.value||'rating';
 if(!currentUser){
  bulkSellMode=false;
  selectedSaleCards.clear();
 }
 const arrSource=currentUser?userCards:cards;
 let arr=arrSource.filter(c=>(r==='all'||c.rarity===r)&&(`${c.name} ${c.short} ${c.year}`.toLowerCase().includes(q)));
 arr.sort((a,b)=>s==='rating'?b.rating-a.rating:s==='year'?b.year-a.year:a.name.localeCompare(b.name));
 const grid=document.getElementById('collectionGrid');if(grid)grid.innerHTML=arr.map(card=>cardHTML(card,Boolean(currentUser))).join('');
 const message=document.getElementById('collectionMessage');if(message)message.textContent=currentUser?(arr.length?`${arr.length} Karten in deiner Sammlung.`:'Noch keine Karten gesammelt. Öffne dein erstes Pack im Shop.'):`${arr.length} Karten in der Katalog-Vorschau. Melde dich an, um eigene Karten zu sammeln und zu verwalten.`;
 const controls=document.getElementById('bulkSaleControls');
 if(controls)controls.hidden=!currentUser;
 const modeButton=document.getElementById('bulkSaleModeButton');
 if(modeButton)modeButton.textContent=bulkSellMode?'AUSWAHL BEENDEN':'MEHRERE VERKAUFEN';
 const status=document.getElementById('bulkSaleStatus');
 if(status)status.textContent=`${selectedSaleCards.size} von ${MAX_BULK_SALE_CARDS} Karten ausgewählt`;
 const sellButton=document.getElementById('bulkSellButton');
 if(sellButton)sellButton.disabled=selectedSaleCards.size===0;
}
function toggleBulkSellMode(){
 if(!currentUser)return showPage('login');
 bulkSellMode=!bulkSellMode;
 if(!bulkSellMode)selectedSaleCards.clear();
 filterCards();
}
function toggleSaleSelection(instanceId,selected){
 if(selected&&!selectedSaleCards.has(instanceId)&&selectedSaleCards.size>=MAX_BULK_SALE_CARDS){
  toast(`Du kannst maximal ${MAX_BULK_SALE_CARDS} Karten gleichzeitig auswählen.`);
  filterCards();
  return;
 }
 if(selected)selectedSaleCards.add(instanceId);
 else selectedSaleCards.delete(instanceId);
 filterCards();
}
async function sellSelectedCards(){
 if(!currentUser||!backendReady())return showPage('login');
 const instanceIds=[...selectedSaleCards];
 if(!instanceIds.length||instanceIds.length>MAX_BULK_SALE_CARDS)return;
 const cardsToSell=instanceIds.map(id=>userCards.find(card=>card.instanceId===id)).filter(Boolean);
 if(cardsToSell.length!==instanceIds.length){
  displayBackendError({message:'Die Auswahl enthält Karten, die nicht mehr in deiner Sammlung sind. Bitte aktualisiere die Seite.'});
  return;
 }
 const total=cardsToSell.reduce((sum,card)=>sum+cardSalePrice(card),0);
 if(!confirm(`${cardsToSell.length} Karten für insgesamt ${total.toLocaleString()} Coins verkaufen?`))return;
 const {data,error}=await supabaseClient.rpc('sell_user_cards',{p_instance_ids:instanceIds});
 if(error)return displayBackendError(error);
 selectedSaleCards.clear();
 bulkSellMode=false;
 await refreshAccountData();
 toast(`${Number(data.coins_awarded).toLocaleString()} Coins für ${Number(data.cards_sold)} Karten erhalten.`);
}
async function sellCard(instanceId){
 if(!currentUser||!backendReady())return showPage('login');
 if(!confirm('Diese Karte zum angezeigten Stufen- und Levelwert verkaufen?'))return;
 const {data,error}=await supabaseClient.rpc('sell_user_card',{p_instance_id:instanceId});
 if(error)return displayBackendError(error);
 selectedSaleCards.delete(instanceId);
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
