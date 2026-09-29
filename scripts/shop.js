function openPurchase(name,cost,type){
 if(!currentUser){setAuthMessage('Zum Packkauf bitte zuerst anmelden.');showPage('login');return}
 selectedPack={name,cost,type};
 document.getElementById('modalName').textContent=name;document.getElementById('modalCost').textContent=cost.toLocaleString();
 document.getElementById('modalPackText').textContent=name.replace(' PACK','');
 document.getElementById('purchaseMessage').innerHTML='';
 document.getElementById('purchaseModal').classList.add('open');
}
function closeModal(){document.getElementById('purchaseModal').classList.remove('open')}
async function buyPack(){
 if(!currentUser||!backendReady())return showPage('login');
 const {data,error}=await supabaseClient.rpc('purchase_pack',{p_tier:selectedPack.type});
 if(error){document.getElementById('purchaseMessage').innerHTML=`<div class="success error">${error.message}</div>`;return}
 const openedCards=(data||[]).map(row=>({instanceId:row.instance_id,name:row.card_name,short:row.short_name,year:row.card_year,rating:row.rating,rarity:row.rarity,type:row.card_type,img:row.image_url,level:row.level}));
 closeModal();
 await refreshAccountData();
 openShowroom(selectedPack.name,selectedPack.type,openedCards);
}
function playOpeningSound(packType){
 const scores={
   bronze:{pad:[73.42,110,146.83,174.61,220],melody:[146.83,174.61,220,293.66,349.23,440,587.33,698.46],volume:.82},
   gold:{pad:[98,146.83,196,246.94,293.66],melody:[196,246.94,293.66,392,493.88,587.33,783.99,987.77],volume:.88},
   platinum:{pad:[82.41,123.47,164.81,196,246.94],melody:[164.81,196,246.94,329.63,392,493.88,659.25,783.99],volume:.92},
   legend:{pad:[110,164.81,220,261.63,329.63],melody:[220,261.63,329.63,440,523.25,659.25,880,1046.5],volume:1}
 };
 const score=scores[packType]||scores.gold;
 const AudioContextClass=window.AudioContext||window.webkitAudioContext;
 if(!AudioContextClass)return;
 if(openingAudioContext)openingAudioContext.close();
 let context;
 try{context=new AudioContextClass();openingAudioContext=context}catch{return}
 const start=context.currentTime;
 const master=context.createGain();
 master.gain.setValueAtTime(score.volume,start);
 master.gain.setValueAtTime(score.volume,start+5.6);
 master.gain.exponentialRampToValueAtTime(.0001,start+6.4);
 const limiter=context.createDynamicsCompressor();
 limiter.threshold.value=-12;limiter.knee.value=10;limiter.ratio.value=7;limiter.attack.value=.003;limiter.release.value=.22;
 master.connect(limiter);limiter.connect(context.destination);

 const padFilter=context.createBiquadFilter();
 padFilter.type='lowpass';padFilter.frequency.setValueAtTime(180,start);padFilter.frequency.exponentialRampToValueAtTime(1500,start+4.8);
 padFilter.connect(master);
 score.pad.forEach((frequency,index)=>{
   const voice=context.createOscillator();
   const voiceGain=context.createGain();
   voice.type=index<2?'sine':'triangle';voice.frequency.value=frequency;
  voiceGain.gain.setValueAtTime(.0001,start);voiceGain.gain.exponentialRampToValueAtTime(.065,start+1.1+index*.12);voiceGain.gain.setValueAtTime(.085,start+4.8);voiceGain.gain.exponentialRampToValueAtTime(.0001,start+6.2);
   voice.connect(voiceGain);voiceGain.connect(padFilter);voice.start(start);voice.stop(start+6.3);
 });

 score.melody.forEach((frequency,index)=>{
   const noteStart=start+.65+index*.48;
   const note=context.createOscillator();
   const noteFilter=context.createBiquadFilter();
   const noteGain=context.createGain();
   note.type='sine';note.frequency.value=frequency;noteFilter.type='lowpass';noteFilter.frequency.value=1800;
  noteGain.gain.setValueAtTime(.0001,noteStart);noteGain.gain.exponentialRampToValueAtTime(.12,noteStart+.035);noteGain.gain.exponentialRampToValueAtTime(.0001,noteStart+.42);
   note.connect(noteFilter);noteFilter.connect(noteGain);noteGain.connect(master);note.start(noteStart);note.stop(noteStart+.44);
 });

 const riser=context.createOscillator();
 const riserFilter=context.createBiquadFilter();
 const riserGain=context.createGain();
 riser.type='sawtooth';riser.frequency.setValueAtTime(42,start);riser.frequency.exponentialRampToValueAtTime(168,start+4.6);riserFilter.type='lowpass';riserFilter.frequency.setValueAtTime(100,start);riserFilter.frequency.exponentialRampToValueAtTime(900,start+4.5);
 riserGain.gain.setValueAtTime(.0001,start);riserGain.gain.exponentialRampToValueAtTime(.065,start+3.8);riserGain.gain.exponentialRampToValueAtTime(.0001,start+5.9);
 riser.connect(riserFilter);riserFilter.connect(riserGain);riserGain.connect(master);riser.start(start);riser.stop(start+6);

 const noiseBuffer=context.createBuffer(1,Math.floor(context.sampleRate*6.4),context.sampleRate);
 const noiseData=noiseBuffer.getChannelData(0);
 for(let i=0;i<noiseData.length;i++)noiseData[i]=Math.random()*2-1;
 const riserNoise=context.createBufferSource();
 const riserNoiseFilter=context.createBiquadFilter();
 const riserNoiseGain=context.createGain();
 riserNoise.buffer=noiseBuffer;riserNoiseFilter.type='bandpass';riserNoiseFilter.frequency.setValueAtTime(180,start);riserNoiseFilter.frequency.exponentialRampToValueAtTime(1300,start+4.5);riserNoiseGain.gain.setValueAtTime(.0001,start);riserNoiseGain.gain.exponentialRampToValueAtTime(.055,start+3.8);riserNoiseGain.gain.exponentialRampToValueAtTime(.0001,start+5.8);
 riserNoise.connect(riserNoiseFilter);riserNoiseFilter.connect(riserNoiseGain);riserNoiseGain.connect(master);riserNoise.start(start);riserNoise.stop(start+6);

 [1.3,2.45,3.8,4.35].forEach((offset,index)=>{
   const strike=start+offset;
   const crack=context.createBufferSource();
   const crackFilter=context.createBiquadFilter();
   const crackGain=context.createGain();
   crack.buffer=noiseBuffer;crackFilter.type='highpass';crackFilter.frequency.value=850+index*220;
  crackGain.gain.setValueAtTime(.42,strike);crackGain.gain.exponentialRampToValueAtTime(.0001,strike+.16);
   crack.connect(crackFilter);crackFilter.connect(crackGain);crackGain.connect(master);crack.start(strike,0,.18);crack.stop(strike+.2);
   const rumble=context.createOscillator();
   const rumbleFilter=context.createBiquadFilter();
   const rumbleGain=context.createGain();
   rumble.type='sine';rumble.frequency.setValueAtTime(90,strike);rumble.frequency.exponentialRampToValueAtTime(35,strike+.42);
  rumbleFilter.type='lowpass';rumbleFilter.frequency.value=180;rumbleGain.gain.setValueAtTime(.38,strike);rumbleGain.gain.exponentialRampToValueAtTime(.0001,strike+.62);
   rumble.connect(rumbleFilter);rumbleFilter.connect(rumbleGain);rumbleGain.connect(master);rumble.start(strike);rumble.stop(strike+.64);
 });
 context.resume().catch(()=>{});
 window.setTimeout(()=>{context.close();if(openingAudioContext===context)openingAudioContext=null},7000);
}
function packArtwork(tier){
 return `<svg class="pack-card-art" viewBox="0 0 400 600" role="img" aria-label="${tier} Formula One collector pack">
   <defs>
     <linearGradient id="packShell" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="var(--pack-light)"/><stop offset=".22" stop-color="var(--pack-metal)"/><stop offset=".48" stop-color="#313545"/><stop offset=".72" stop-color="var(--pack-metal)"/><stop offset="1" stop-color="var(--pack-light)"/></linearGradient>
     <linearGradient id="packGlass" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#102344"/><stop offset=".48" stop-color="var(--pack-dark)"/><stop offset="1" stop-color="#070911"/></linearGradient>
     <linearGradient id="packSpectrum" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="var(--pack-holo)" stop-opacity="0"/><stop offset=".46" stop-color="var(--pack-light)" stop-opacity=".95"/><stop offset=".53" stop-color="var(--pack-holo)" stop-opacity=".92"/><stop offset="1" stop-color="var(--pack-holo)" stop-opacity="0"/></linearGradient>
     <clipPath id="packClip"><path d="M200 15 C183 38 169 57 145 51 C108 42 73 37 43 42 Q27 45 27 64 L27 468 Q27 499 53 515 L200 585 L347 515 Q373 499 373 468 L373 64 Q373 45 357 42 C327 37 292 42 255 51 C231 57 217 38 200 15Z"/></clipPath>
   </defs>
   <path class="shield-shell" d="M200 15 C183 38 169 57 145 51 C108 42 73 37 43 42 Q27 45 27 64 L27 468 Q27 499 53 515 L200 585 L347 515 Q373 499 373 468 L373 64 Q373 45 357 42 C327 37 292 42 255 51 C231 57 217 38 200 15Z"/>
   <g clip-path="url(#packClip)">
     <path class="shield-inner" d="M200 35 C181 57 165 73 142 67 C107 58 82 55 48 59 L48 462 Q48 485 68 497 L200 560 L332 497 Q352 485 352 462 L352 59 C318 55 293 58 258 67 C235 73 219 57 200 35Z"/>
     <path class="pack-spectrum" d="M5 306 L358 104 L410 172 L57 374Z"/>
     <path class="pack-ribbon" d="M8 365 C102 323 183 253 391 165"/>
     <path class="pack-ribbon secondary" d="M10 378 C112 335 211 265 394 184"/>
     <path class="pack-ribbon" d="M74 432 C176 374 276 315 391 260"/>
     <path class="pack-nameplate" d="M35 406 Q200 390 365 406 L365 484 Q200 497 35 484Z"/>
     <path class="pack-sheen" d="M12 192 L383 66 L389 83 L18 209Z" fill="url(#packSpectrum)"/>
   </g>
   <path class="shield-rim" d="M200 28 C180 51 165 64 144 59 C108 50 76 48 40 53 L40 466 Q40 493 61 506 L200 572 L339 506 Q360 493 360 466 L360 53 C324 48 292 50 256 59 C235 64 220 51 200 28Z"/>
  <image class="pack-logo" href="zfc-logo.svg" x="64" y="73" width="272" height="82" preserveAspectRatio="xMidYMid meet"/>
   <text class="pack-mark" x="200" y="300" text-anchor="middle">F1</text>
   <text class="pack-tier-label" x="200" y="451" text-anchor="middle">${tier.toUpperCase()} SERIES</text>
   <text class="pack-sub-label" x="200" y="477" text-anchor="middle">WORLD CHAMPIONSHIP EDITION</text>
 </svg>`;
}
function launchRevealConfetti(){
 const layer=document.getElementById('revealConfetti');
 const colors=['#ff243f','#ffd75a','#f5f7ff','#55dfff','#ff63c8'];
 for(let i=0;i<72;i++){
   const fromLeft=i%2===0;
   const piece=document.createElement('span');
   piece.className='confetti-piece';
   piece.style.left=fromLeft?'0':'auto';
   piece.style.right=fromLeft?'auto':'0';
   piece.style.top=`${24+Math.random()*54}%`;
   piece.style.setProperty('--piece-color',colors[i%colors.length]);
   piece.style.setProperty('--piece-width',`${5+Math.random()*7}px`);
   piece.style.setProperty('--piece-height',`${8+Math.random()*11}px`);
   piece.style.setProperty('--drift',`${(fromLeft?1:-1)*window.innerWidth*(.32+Math.random()*.5)}px`);
   piece.style.setProperty('--fall',`${(Math.random()-.5)*window.innerHeight*.42}px`);
   piece.style.setProperty('--spin',`${360+Math.random()*1080}deg`);
   piece.style.setProperty('--duration',`${1.2+Math.random()*.7}s`);
   piece.style.setProperty('--delay',`${Math.random()*.32}s`);
   layer.append(piece);
 }
}
function openShowroom(packName,packType,openedCards=null){
 document.getElementById('showPackName').textContent=packName;
 const showroom=document.querySelector('.showroom');
 const openingCards=document.getElementById('openingCards');
 const confetti=document.getElementById('revealConfetti');
 const tier=['bronze','gold','platinum','legend'].includes(packType)?packType:'gold';
 const reducedMotion=window.matchMedia('(prefers-reduced-motion: reduce)').matches;
 showroom.dataset.packTier=tier;
 showroom.classList.remove('opening-active','revealed','cards-visible','stage-finished');
 document.querySelector('.sequence-pack').innerHTML=packArtwork(tier);
 clearTimeout(showroomTimer);clearInterval(showroomCountdown);clearTimeout(confettiTimer);clearTimeout(confettiCleanupTimer);clearTimeout(inspectTimer);clearTimeout(stageFinishTimer);
 openingCards.innerHTML='';openingCards.classList.remove('inspecting');confetti.replaceChildren();
 showroom.classList.add('opening-active');
 showPage('showroom');
 playOpeningSound(tier);
 const revealCards=()=>{
  const pool=openedCards?.length?openedCards:cards.slice().sort(()=>Math.random()-.5).slice(0,5);
   openingCards.innerHTML=pool.map((c,i)=>`<div class="opening-card${cardTier(c)==='legend'?' legendary-reveal':''}" style="--index:${i};--delay:${reducedMotion?0:i*.42}s">${cardHTML(c)}</div>`).join('');
  showroom.classList.remove('opening-active');
  showroom.classList.add('cards-visible');
   if(reducedMotion){openingCards.classList.add('inspecting');showroom.classList.add('stage-finished','revealed');return}
   confettiTimer=setTimeout(()=>{
     launchRevealConfetti();
     inspectTimer=setTimeout(()=>openingCards.classList.add('inspecting'),550);
     stageFinishTimer=setTimeout(()=>showroom.classList.add('stage-finished','revealed'),2400);
     confettiCleanupTimer=setTimeout(()=>confetti.replaceChildren(),2300);
   },(pool.length-1)*420+950);
 };
 if(reducedMotion){showroomTimer=setTimeout(revealCards,0);return}
 const endsAt=Date.now()+5000;
 const countdown=document.getElementById('sequenceCountdown');
 countdown.textContent='LICHTER AUS IN 5';
 showroomCountdown=setInterval(()=>{
   const remaining=Math.max(0,Math.ceil((endsAt-Date.now())/1000));
   countdown.textContent=remaining?`LICHTER AUS IN ${remaining}`:'LICHTER AUS';
   if(!remaining)clearInterval(showroomCountdown);
 },250);
 showroomTimer=setTimeout(revealCards,5000);
}
