function playZfcOpening(){
 const opening=document.getElementById('zfcOpening');
 const skipButton=document.getElementById('zfcOpeningSkip');
 if(!opening||!skipButton)return;
 const reducedMotion=window.matchMedia?.('(prefers-reduced-motion: reduce)').matches||false;
 let closeTimer;
 const closeOpening=()=>{
	 window.clearTimeout(closeTimer);
	 opening.classList.add('is-closing');
	 window.setTimeout(()=>opening.remove(),reducedMotion?20:550);
 };
 skipButton.addEventListener('click',closeOpening,{once:true});
 opening.classList.add('is-active');
 skipButton.focus({preventScroll:true});
 closeTimer=window.setTimeout(closeOpening,reducedMotion?80:3600);
}

playZfcOpening();
document.getElementById('purchaseModal').addEventListener('click',e=>{if(e.target.id==='purchaseModal')closeModal()});
render();updateConvert();
initializeBackend();
