function cardTier(c){
 if(c.rating>=96)return 'legend';
 if(c.rating>=90)return 'platinum';
 if(c.rating>=85)return 'gold';
 return 'bronze';
}
function cardLivery(c){
 const name=`${c.name||''} ${c.short||''}`.toLowerCase();
 return ['mclaren','ferrari','mercedes','red bull','racing bulls','alpine','haas','audi','aston martin','williams','cadillac'].find(team=>name.includes(team))?.replaceAll(' ','-')||'';
}
function cardHTML(c, showSale = false){
 const tier=cardTier(c);
 const livery=cardLivery(c);
 const cardType=String(c.type||'').toUpperCase();
 const dataType=cardType==='TEAM'?'team':cardType==='CAR'?'car':'driver';
 const category=cardType==='TEAM'?'TEAM':cardType==='CAR'?'LIVERY':'DRIVER';
 const photoClass=cardType==='TEAM'?'team-photo':cardType==='CAR'?'car-photo':'driver-photo';
 const level=Number(c.level||1);
 const tierBase={bronze:100,gold:250,platinum:500,legend:1000}[tier];
 const saleEstimate=tierBase+(c.rating*5)+((level-1)*75);
 const levelMarkup=showSale?`<div class="card-level">LEVEL ${level}</div>`:'';
 const actionMarkup=showSale?`<div class="owned-card-actions">${level<10?`<button class="upgrade-card" onclick="event.stopPropagation();upgradeCard('${c.instanceId}')">LEVEL UP · ${(level*300).toLocaleString()} C</button>`:''}<button class="sell-card" onclick="event.stopPropagation();sellCard('${c.instanceId}')">VERKAUFEN · ${saleEstimate.toLocaleString()} C</button></div>`:'';
 const photoMarkup=cardType==='TEAM'
	 ?`<div class="photo team-photo"><img src="${c.img}" alt="${c.name} Logo" loading="lazy"></div>`
	 :`<div class="photo ${photoClass}"><img class="photo-image" src="${c.img}" alt="${c.name}" loading="lazy"></div>`;
 const cardMarkup=`<div class="card ${c.rarity} tier-${tier}${livery?` livery-${livery}`:''}${showSale?' owned-card':''}" data-tier="${tier}" data-card-type="${dataType}"><span class="card-red-neon" aria-hidden="true"></span><div class="card-media">${photoMarkup}<div class="rating"><span>OVR</span><b>${c.rating}</b></div><div class="rarity">${category}</div>${levelMarkup}</div><div class="info"><div class="name">${c.short}</div><div class="year">${c.name} · ${c.year}</div></div><div class="card-specs"><div><span>RATING</span><b>${c.rating}</b></div><div><span>SAISON</span><b>${c.year}</b></div><div><span>KARTE</span><b>${category}</b></div><div><span>STUFE</span><b>${tier.toUpperCase()}</b></div></div></div>`;
 return showSale?`<div class="owned-card-item">${cardMarkup}${actionMarkup}</div>`:cardMarkup;
}
function render(){
 const currentCars=cards.filter(card=>card.year===2026&&card.type==='CAR').slice(0,3);
 const currentTeams=cards.filter(card=>card.year===2026&&card.type==='TEAM').slice(0,2);
 const featuredCards=[...currentCars,...currentTeams];
 document.getElementById('homeCards').innerHTML=(featuredCards.length?featuredCards:cards.slice(0,5)).map(cardHTML).join('');
 const dashboardCards=currentUser?userCards.slice(0,5):cards.slice(0,5);
 document.getElementById('dashCards').innerHTML=dashboardCards.map(card=>cardHTML(card)).join('');
 filterCards();
}
