const S={entries:[],qs:[],i:0,ok:0,errors:[],locked:false,prompt:null};
const $=id=>document.getElementById(id);
const screens=['setup','quiz','result','history'];
function show(id){screens.forEach(x=>$(x).classList.toggle('hidden',x!==id))}
function norm(v){return String(v).trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[’']/g,"'").replace(/[.,;:!?()[\]{}"]/g,'').replace(/\s+/g,' ')}
function answers(v){const s=new Set([norm(v)]);String(v).split(';').forEach(x=>s.add(norm(x)));String(v).split(' / ').forEach(x=>s.add(norm(x)));return [...s]}
function esc(v){return String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]))}
function shuffle(a){a=[...a];for(let i=a.length-1;i;i--){const j=Math.floor(Math.random()*(i+1));[a[i],a[j]]=[a[j],a[i]]}return a}
async function load(){
 try{
  const r=await fetch('daten/band4_unite1.json'); if(!r.ok)throw Error();
  const d=await r.json(); S.entries=d.entries;
  const secs=[...new Set(S.entries.map(e=>e.section))];
  $('section').innerHTML='<option value="all">Alle Bereiche</option>'+secs.map(x=>`<option>${esc(x)}</option>`).join('');
  $('status').textContent=`${S.entries.length} Einträge aus Band 4 · Unité 1 geladen.`;
 }catch{$('status').textContent='Fehler beim Laden. Bitte über einen Webserver öffnen.';$('start').disabled=true}
}
function start(){
 const sec=$('section').value, extra=$('extra').checked, dir=$('direction').value;
 let pool=S.entries.filter(e=>(sec==='all'||e.section===sec)&&(extra||e.learning_vocabulary));
 if(!pool.length)return alert('Keine Vokabeln für diese Auswahl.');
 const cv=$('count').value,n=cv==='all'?pool.length:Math.min(+cv,pool.length);
 S.qs=shuffle(pool).slice(0,n).map(e=>({e,d:dir==='mixed'?(Math.random()<.5?'de-fr':'fr-de'):dir}));
 S.i=0;S.ok=0;S.errors=[];show('quiz');render();
}
function render(){
 const q=S.qs[S.i],de=q.d==='de-fr';
 $('question').textContent=de?q.e.de:q.e.fr;
 $('progress').textContent=`Frage ${S.i+1} von ${S.qs.length}`;
 $('score').textContent=`${S.ok} richtig`;
 $('bar').style.width=`${S.i/S.qs.length*100}%`;
 $('answer').value='';$('answer').disabled=false;$('submit').textContent='Prüfen';
 $('feedback').className='feedback hidden';S.locked=false;setTimeout(()=>$('answer').focus(),30);
}
function check(){
 if(S.locked){S.i++;return S.i>=S.qs.length?finish():render()}
 const q=S.qs[S.i],de=q.d==='de-fr',expected=de?q.e.fr:q.e.de,prompt=de?q.e.de:q.e.fr,a=$('answer').value;
 if(!a.trim())return;
 const ok=answers(expected).includes(norm(a)),f=$('feedback');f.className='feedback '+(ok?'correct':'wrong');
 if(ok){S.ok++;f.textContent='Richtig!'}else{S.errors.push({prompt,a,expected});f.innerHTML=`Nicht ganz. Richtig: <strong>${esc(expected)}</strong>`}
 $('score').textContent=`${S.ok} richtig`;$('answer').disabled=true;$('submit').textContent=S.i+1===S.qs.length?'Ergebnis anzeigen':'Weiter';S.locked=true;
}
function finish(){
 const total=S.qs.length,p=Math.round(S.ok/total*100);
 $('percent').textContent=p+' %';$('summary').textContent=`${S.ok} von ${total} Antworten waren richtig.`;
 $('mistakes').innerHTML=S.errors.length?'<h3>Fehlerübersicht</h3>'+S.errors.map(x=>`<div class="mistake"><b>${esc(x.prompt)}</b><br>Deine Antwort: ${esc(x.a)}<br>Richtig: ${esc(x.expected)}</div>`).join(''):'<p>Sehr gut – keine Fehler.</p>';
 const h=JSON.parse(localStorage.getItem('aplus-history')||'[]');h.unshift({date:new Date().toISOString(),p,ok:S.ok,total,sec:$('section').selectedOptions[0].textContent});localStorage.setItem('aplus-history',JSON.stringify(h.slice(0,20)));show('result');
}
function history(){
 const h=JSON.parse(localStorage.getItem('aplus-history')||'[]');
 $('historyList').innerHTML=h.length?h.map(x=>`<div class="history-item"><b>${x.p} % · ${x.ok}/${x.total}</b><br><small>${new Date(x.date).toLocaleDateString('de-DE')} · ${esc(x.sec)}</small></div>`).join(''):'<p>Noch keine Ergebnisse gespeichert.</p>';show('history');
}
$('start').onclick=start;$('submit').onclick=check;$('answer').onkeydown=e=>{if(e.key==='Enter')check()};$('quit').onclick=() => show('setup');$('again').onclick=()=>show('setup');$('historyBtn').onclick=history;$('back').onclick=()=>show('setup');$('clear').onclick=()=>{if(confirm('Verlauf löschen?')){localStorage.removeItem('aplus-history');history()}};
function net(){$('net').textContent=navigator.onLine?'Online':'Offline'}addEventListener('online',net);addEventListener('offline',net);net();
if('serviceWorker'in navigator)addEventListener('load',()=>navigator.serviceWorker.register('sw.js'));
addEventListener('beforeinstallprompt',e=>{e.preventDefault();S.prompt=e;$('install').hidden=false});
$('install').onclick=async()=>{if(S.prompt){S.prompt.prompt();await S.prompt.userChoice;S.prompt=null;$('install').hidden=true}};
load();