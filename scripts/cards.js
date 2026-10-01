function cardTier(c){
 if(c.rating>=96)return 'legend';
 if(c.rating>=90)return 'platinum';
 if(c.rating>=85)return 'gold';
 return 'bronze';
}
function cardHTML(c, showSale = false){
 const tier=cardTier(c);
 const level=Number(c.level||1);
 const tierBase={bronze:100,gold:250,platinum:500,legend:1000}[tier];
 const saleEstimate=tierBase+(c.rating*5)+((level-1)*75);
 const levelMarkup=showSale?`<div class="card-level">LEVEL ${level}</div>`:'';
 const actionMarkup=showSale?`<div class="owned-card-actions">${level<10?`<button class="upgrade-card" onclick="event.stopPropagation();upgradeCard('${c.instanceId}')">LEVEL UP · ${(level*300).toLocaleString()} C</button>`:''}<button class="sell-card" onclick="event.stopPropagation();sellCard('${c.instanceId}')">VERKAUFEN · ${saleEstimate.toLocaleString()} C</button></div>`:'';
 const photoMarkup=c.type==='TEAM'
	 ?`<div class="photo team-photo"><img src="${c.img}" alt="${c.name} Logo" loading="lazy"></div>`
	 :`<div class="photo" style="background-image:url('${c.img}')"></div>`;
 const cardMarkup=`<div class="card ${c.rarity} tier-${tier}${showSale?' owned-card':''}" data-tier="${tier}"><span class="card-red-neon" aria-hidden="true"></span>${photoMarkup}<div class="rating">${c.rating}</div><div class="rarity">${c.type}</div>${levelMarkup}<div class="info"><div class="name">${c.short}</div><div class="year">${c.year}</div></div><div class="type">${tier.toUpperCase()}</div></div>`;
 return showSale?`<div class="owned-card-item">${cardMarkup}${actionMarkup}</div>`:cardMarkup;
}
function render(){
 document.getElementById('homeCards').innerHTML=cards.slice(0,5).map(cardHTML).join('');
 const dashboardCards=currentUser?userCards.slice(0,5):cards.slice(0,5);
 document.getElementById('dashCards').innerHTML=dashboardCards.map(card=>cardHTML(card)).join('');
 filterCards();
}
